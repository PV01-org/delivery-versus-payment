// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
██████╗░██╗░░░██╗██████╗░███████╗░█████╗░░██████╗██╗░░░██╗░░░██╗░░██╗██╗░░░██╗███████╗
██╔══██╗██║░░░██║██╔══██╗██╔════╝██╔══██╗██╔════╝╚██╗░██╔╝░░░╚██╗██╔╝╚██╗░██╔╝╚════██║
██║░░██║╚██╗░██╔╝██████╔╝█████╗░░███████║╚█████╗░░╚████╔╝░░░░░╚███╔╝░░╚████╔╝░░░███╔═╝
██║░░██║░╚████╔╝░██╔═══╝░██╔══╝░░██╔══██║░╚═══██╗░░╚██╔╝░░░░░░██╔██╗░░░╚██╔╝░░██╔══╝░░
██████╔╝░░╚██╔╝░░██║░░░░░███████╗██║░░██║██████╔╝░░░██║░░░██╗██╔╝╚██╗░░░██║░░░███████╗
╚═════╝░░░░╚═╝░░░╚═╝░░░░░╚══════╝╚═╝░░╚═╝╚═════╝░░░░╚═╝░░░╚═╝╚═╝░░╚═╝░░░╚═╝░░░╚══════╝
 */

import {Address} from "@openzeppelin/contracts-v5-2-0/utils/Address.sol";
import {ERC165Checker} from "@openzeppelin/contracts-v5-2-0/utils/introspection/ERC165Checker.sol";
import {IDeliveryVersusPaymentV1} from "./IDeliveryVersusPaymentV1.sol";
import {IERC20} from "@openzeppelin/contracts-v5-2-0/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts-v5-2-0/token/ERC721/IERC721.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts-v5-2-0/utils/ReentrancyGuardTransient.sol";
import {SafeERC20} from "@openzeppelin/contracts-v5-2-0/token/ERC20/utils/SafeERC20.sol";

/**
 * @title DeliveryVersusPaymentV1
 * @dev Delivery Versus Payment implementation for ERC-20, ERC-721 and Ether transfers.
 * Created by https://pv0.one. UI implemented at https://dvpeasy.xyz.
 *
 * Workflow Summary:
 *
 * 1) Create a Settlement
 * A settlement is collection of intended value transfers (Flows) between parties, along with a free text
 * reference, a deadline (cutoff date) and an auto-settlement flag indicating if settlement should be immediately
 * processed after final approval received. ERC-20, ERC-721 and Ether transfers are supported.
 * For example a settlement could include the following 3 flows, be set to expire in 1 week, and be auto-settled
 * when all "from" parties (sender addresses) have approved:
 * ------------------------------------------------
 *   From    -> To       AmountOrId  Token   isNFT
 * ------------------------------------------------
 *   Alice   -> Bob      1           ETH     false
 *   Bob     -> Charlie  400         TokenA  false
 *   Charlie -> Alice    500(id)     TokenB  true
 * If a token claims to be an NFT and is not, the creation will revert.
 * If a token claims to be an ERC20, but doesn't implement decimals(), the creation will revert.
 *
 * 2) Approve a Settlement
 * Each party who is a "from" address in one or more flows needs to approve the settlement before it can proceed.
 * They do this by calling approveSettlements() and including their necessary total ETH deposit if their flows involve
 * sending ETH. ERC-20 and ERC-721 tokens are not deposited upfront, they only need transfer approval before execution.
 * If a settlement is marked as isAutoSettled:
 *  - the settlement will be executed automatically after all approvals are in place, the gas cost being borne
 *    by the last approver.
 *  - if settlement approval succeeds, but auto-execution fails, the entire transaction is not reverted. The approval
 *    remains on-chain, only the settlement execution is reverted.
 *
 * 3) Execute a Settlement
 * Anyone can call executeSettlement() before the cutoff date, if all approvals are in place. At execution time the
 * contract makes the transfers in an atomic, all or nothing, manner. If any Flow transfer fails the entire settlement
 * is reverted.
 *
 * 4) Changes
 * If a party changes their mind before the settlement is fully executed — and before the cutoff date — they can revoke
 * their approval by calling revokeApprovals(). This returns any deposited ETH back to them and removes their approval.
 * Once expired a settlement can no longer be executed, any ETH deposited can be withdrawn by each party using withdrawETH().
 *
 * NB There are many unbounded loops in this contract, by design. There is no limit on the number of flows in a settlement,
 * nor on how many settlements can be batch processed (for functions that receive an array of settlementIds). The current
 * chain's block gas limit acts as a cap. In every case it is the caller's responsibility to ensure that the gas requirement
 * can be met.
 */
contract DeliveryVersusPaymentV1 is IDeliveryVersusPaymentV1, ReentrancyGuardTransient {
  using SafeERC20 for IERC20;
  using ERC165Checker for address;

  event ETHReceived(address indexed party, uint256 amount);
  event ETHWithdrawn(address indexed party, uint256 amount);
  event SettlementApproved(uint256 indexed settlementId, address indexed party);
  event SettlementCreated(uint256 indexed settlementId, address indexed creator);
  event SettlementExecuted(uint256 indexed settlementId, address indexed executor);
  event SettlementAutoExecutionFailedReason(uint256 indexed settlementId, address indexed executor, string reason);
  event SettlementAutoExecutionFailedPanic(uint256 indexed settlementId, address indexed executor, uint errorCode);
  event SettlementAutoExecutionFailedOther(uint256 indexed settlementId, address indexed executor, bytes lowLevelData);
  event SettlementApprovalRevoked(uint256 indexed settlementId, address indexed party);

  // Custom Errors
  error ApprovalAlreadyGranted();
  error ApprovalNotGranted();
  error CallerNotInvolved();
  error CallerMustBeDvpContract();
  error CannotSendEtherDirectly();
  error CutoffDateNotPassed();
  error CutoffDatePassed();
  error IncorrectETHAmount();
  error InvalidERC20Token();
  error InvalidERC721Token();
  error NoETHToWithdraw();
  error NoFlowsProvided();
  error SettlementAlreadyExecuted();
  error SettlementDoesNotExist();
  error SettlementNotApproved();

  /**
   * @dev TokenStatus contains an assessment of how ready a party is to settle, for a particular token.
   */
  struct TokenStatus {
    address tokenAddress;
    bool isNFT;
    /// @dev Amount or ID required for the settlement
    uint256 amountOrIdRequired;
    /// @dev Amount or ID already approved for DVP by the party
    uint256 amountOrIdApprovedForDvp;
    /// @dev Total amount or ID held by the party
    uint256 amountOrIdHeldByParty;
  }

  /**
   * @dev A Settlement is a collection of Flows together with a free text reference, a cutoff date,
   * an auto-settlement flag, and mappings for approvals and a record of ETH deposits.
   * A settlement is uniquely identified by its settlementId.
   */
  struct Settlement {
    string settlementReference;
    uint256 cutoffDate;
    Flow[] flows;
    mapping(address => bool) approvals;
    mapping(address => uint256) ethDeposits;
    bool isSettled;
    bool isAutoSettled;
  }
  mapping(uint256 => Settlement) private settlements;

  /// @dev Last settlement id used
  uint256 public settlementIdCounter;

  /// @dev selector for decimals() function in ERC-20 tokens
  bytes4 private constant SELECTOR_ERC20_DECIMALS = bytes4(keccak256("decimals()"));

  //------------------------------------------------------------------------------
  // Public
  //------------------------------------------------------------------------------
  /**
   * @dev Checks if all parties have approved the settlement.
   * @param settlementId The id of the settlement to check.
   */
  function isSettlementApproved(uint256 settlementId) public view returns (bool) {
    Settlement storage settlement = settlements[settlementId];
    if (settlement.flows.length == 0) revert SettlementDoesNotExist();

    uint256 lengthFlows = settlement.flows.length;
    for (uint256 i = 0; i < lengthFlows; i++) {
      address party = settlement.flows[i].from;
      if (!settlement.approvals[party]) {
        return false;
      }
    }
    return true;
  }

  //------------------------------------------------------------------------------
  // External
  //------------------------------------------------------------------------------
  /**
   * @dev Approves multiple settlements and sends exact required ETH deposits. To find out how much ETH to send with
   * an approval, call function getSettlementPartyStatus() first. If a settlement is marked as auto-settled,
   * and this is the final approval, then the settlement will also be executed.
   * NB:
   * 1) It is the caller's responsibility to ensure that, if they are final approver in an auto-settled settlement,
   * then any gas requirement can be met.
   * 2) If approval succeeds, but settlement fails, the entire transaction is NOT reverted. Approvals remain and
   * the settlement can be executed later.
   * @param settlementIds The ids of the settlements to approve.
   */
  function approveSettlements(uint256[] calldata settlementIds) external payable nonReentrant {
    uint256 totalEthRequired;

    uint256 lengthSettlements = settlementIds.length;
    for (uint256 i = 0; i < lengthSettlements; i++) {
      uint256 settlementId = settlementIds[i];
      Settlement storage settlement = settlements[settlementId];

      uint256 lengthFlows = settlement.flows.length;
      if (lengthFlows == 0) revert SettlementDoesNotExist();
      if (settlement.isSettled) revert SettlementAlreadyExecuted();
      if (block.timestamp > settlement.cutoffDate) revert CutoffDatePassed();
      if (settlement.approvals[msg.sender]) revert ApprovalAlreadyGranted();

      uint256 ethAmountRequired = 0;
      bool isInvolved = false;

      for (uint256 j = 0; j < lengthFlows; j++) {
        Flow storage flow = settlement.flows[j];
        if (flow.from == msg.sender) {
          isInvolved = true;
          if (flow.token == address(0)) {
            ethAmountRequired += flow.amountOrId;
          }
        }
      }

      if (!isInvolved) revert CallerNotInvolved();

      totalEthRequired += ethAmountRequired;
      settlement.approvals[msg.sender] = true;
      if (ethAmountRequired > 0) {
        settlement.ethDeposits[msg.sender] += ethAmountRequired;
      }

      emit SettlementApproved(settlementId, msg.sender);
    }

    if (msg.value != totalEthRequired) revert IncorrectETHAmount();
    if (msg.value > 0) {
      emit ETHReceived(msg.sender, msg.value);
    }

    // For any settlement: if we're last approver, and auto settlement is enabled, then execute that settlement
    for (uint256 i = 0; i < lengthSettlements; i++) {
      uint256 settlementId = settlementIds[i];
      Settlement storage settlement = settlements[settlementId];
      if (settlement.isAutoSettled && isSettlementApproved(settlementId)) {
        // Failed auto-execution will not revert the entire transaction, only that settlement's execution will fail.
        // Other settlements will still be processed, and the earlier approval will remain. Note that try{} only
        // supports external/public calls.
        try this.executeSettlementInner(msg.sender, settlementId) {
          // Success
        } catch Error(string memory reason) {
          // Revert with reason string
          emit SettlementAutoExecutionFailedReason(settlementId, msg.sender, reason);
        } catch Panic(uint errorCode) {
          // Revert due to serious error (eg division by zero)
          emit SettlementAutoExecutionFailedPanic(settlementId, msg.sender, errorCode);
        } catch (bytes memory lowLevelData) {
          // Revert in every other case (eg custom error)
          emit SettlementAutoExecutionFailedOther(settlementId, msg.sender, lowLevelData);
        }
      }
    }
  }

  /**
   * @dev Creates a new settlement with the specified flows and cutoff date.
   * Reverts if cutoff date is in the past, no flows are provided, or a claimed NFT token is not
   * and NFT. There is intentionally no limit on the number of flows, the current chain's block
   * gas limit acts as a cap for the max flows.
   * @param flows The flows to include in the settlement.
   * @param settlementReference A free text reference for the settlement.
   * @param cutoffDate The deadline for approvals and execution.
   * @param isAutoSettled If true, the settlement will be executed automatically after all approvals are in place.
   */
  function createSettlement(
    Flow[] calldata flows,
    string calldata settlementReference,
    uint256 cutoffDate,
    bool isAutoSettled
  ) external returns (uint256 id) {
    if (block.timestamp > cutoffDate) revert CutoffDatePassed();
    uint256 lengthFlows = flows.length;
    if (lengthFlows == 0) revert NoFlowsProvided();

    // Validate flows
    for (uint256 i = 0; i < lengthFlows; i++) {
      Flow calldata flow = flows[i];
      if (flow.isNFT) {
        if (!_isERC721(flow.token)) revert InvalidERC721Token();
      } else if (flow.token != address(0)) {
        if (!_isERC20(flow.token)) revert InvalidERC20Token();
      }
    }

    // Store new settlement
    id = ++settlementIdCounter;
    Settlement storage settlement = settlements[id];
    settlement.settlementReference = settlementReference;
    settlement.cutoffDate = cutoffDate;
    settlement.isAutoSettled = isAutoSettled;
    settlement.flows = flows; // needs "via IR" compilation

    emit SettlementCreated(id, msg.sender);
  }

  /**
   * @dev Executes the settlement if all approvals are in place.
   * @param settlementId The id of the settlement to execute.
   */
  function executeSettlement(uint256 settlementId) external nonReentrant {
    this.executeSettlementInner(msg.sender, settlementId);
  }

  /**
   * @dev Execute a single settlement. This is an external function, so that it can be used
   * inside a try/catch, but it behaves like an internal function, in that the caller must
   * be the self contract or the call with revert.
   */
  function executeSettlementInner(address originalCaller, uint256 settlementId) external {
    // this function can only be called by the DVP contract itself
    if (msg.sender != address(this)) {
      revert CallerMustBeDvpContract();
    }
    Settlement storage settlement = settlements[settlementId];
    if (settlement.flows.length == 0) revert SettlementDoesNotExist();
    if (block.timestamp > settlement.cutoffDate) revert CutoffDatePassed();
    if (settlement.isSettled) revert SettlementAlreadyExecuted();
    if (!isSettlementApproved(settlementId)) revert SettlementNotApproved();

    uint256 lengthFlows = settlement.flows.length;
    for (uint256 i = 0; i < lengthFlows; i++) {
      Flow storage flow = settlement.flows[i];
      if (flow.token == address(0)) {
        // ETH Transfer
        // Note: settlement.ethDeposits[flow.from] must == flow.amount, otherwise approval would not have been
        // possible and isSettlementApproved() would have failed. So no need to check for insufficient balance.
        uint256 amount = flow.amountOrId;
        settlement.ethDeposits[flow.from] -= amount;
        // sendValue reverts if unsuccessful
        Address.sendValue(payable(flow.to), amount);
      } else {
        // ERC-721 or ERC-20 transfer in the same way (must cast to IERC20 for OZ safeTransfer for ERC-20)
        IERC20 eitherToken = IERC20(flow.token);
        // safeTransfer reverts if unsuccessful for ERC-20 and ERC-721
        eitherToken.safeTransferFrom(flow.from, flow.to, flow.amountOrId);
      }
    }

    settlement.isSettled = true;
    emit SettlementExecuted(settlementId, originalCaller);
  }

  /**
   * @dev Retrieves settlement details.
   * @param settlementId The id of the settlement to retrieve.
   */
  function getSettlement(
    uint256 settlementId
  )
    external
    view
    returns (
      string memory settlementReference,
      uint256 cutoffDate,
      Flow[] memory flows,
      bool isSettled,
      bool isAutoSettled
    )
  {
    Settlement storage settlement = settlements[settlementId];
    if (settlement.flows.length == 0) revert SettlementDoesNotExist();
    return (
      settlement.settlementReference,
      settlement.cutoffDate,
      settlement.flows,
      settlement.isSettled,
      settlement.isAutoSettled
    );
  }

  /**
   * @dev Provides a view of how ready a party is for a settlement to be executed:
   *   1) If they have approved the settlement
   *   2) How much ETH is required from them and how much they've deposited
   *   3) For each distinct ERC-20 token they must send, how much they need, how much they've allowed DVP to spend, and...
   *   4) ...how much they currently hold of that token
   *   5) For each distinct ERC-721 token they must send, which token they need, if they've allowed DVP to spend it yet, and...
   *   6) ...if the currenly hold that token
   * NB: This function is not intended to be called inside a state-changing transaction, this view is for external callers
   * only, so gas consumption is not critical.
   * It is caller's responsibility to check party is involved in the settlement (check flows in getSettlement).
   * Reverts if settlement does not exist.
   * @param settlementId The id of the settlement to check.
   * @param party The party to check.
   */
  function getSettlementPartyStatus(
    uint256 settlementId,
    address party
  )
    external
    view
    returns (bool isApproved, uint256 etherRequired, uint256 etherDeposited, TokenStatus[] memory tokenStatuses)
  {
    Settlement storage settlement = settlements[settlementId];
    if (settlement.flows.length == 0) revert SettlementDoesNotExist();

    isApproved = settlement.approvals[party];
    (etherRequired, etherDeposited) = _getPartyEthStats(settlement, party);
    tokenStatuses = _getTokenStatuses(settlement, party);
    return (isApproved, etherRequired, etherDeposited, tokenStatuses);
  }

  /**
   * @dev Check if a token is ERC-721
   * @param token The address of the token to check.
   * @return True if the token is ERC-721, false otherwise.
   */
  function isERC721(address token) external view returns (bool) {
    return _isERC721(token);
  }

  /**
   * @dev Check if token is potentially ERC-20. This is a heuristic, not a guarantee.
   * ERC-20 tokens that do not return a valid value from `decimals()` will be misclassified.
   * @param token The address of the token to check.
   * @return True if the token is potentially ERC-20, false otherwise.
   */
  function isERC20(address token) external view returns (bool) {
    return _isERC20(token);
  }

  /**
   * @dev Revokes approvals for multiple settlements and refunds ETH deposits.
   * @param settlementIds The ids of the settlements to revoke approvals for.
   */
  function revokeApprovals(uint256[] calldata settlementIds) external nonReentrant {
    uint256 lengthSettlements = settlementIds.length;
    for (uint256 i = 0; i < lengthSettlements; i++) {
      uint256 settlementId = settlementIds[i];
      Settlement storage settlement = settlements[settlementId];
      if (settlement.flows.length == 0) revert SettlementDoesNotExist();
      if (settlement.isSettled) revert SettlementAlreadyExecuted();
      if (!settlement.approvals[msg.sender]) revert ApprovalNotGranted();

      uint256 ethAmountToRefund = settlement.ethDeposits[msg.sender];
      if (ethAmountToRefund > 0) {
        settlement.ethDeposits[msg.sender] = 0;
        // sendValue reverts if unsuccessful
        Address.sendValue(payable(msg.sender), ethAmountToRefund);
        emit ETHWithdrawn(msg.sender, ethAmountToRefund);
      }

      settlement.approvals[msg.sender] = false;
      emit SettlementApprovalRevoked(settlementId, msg.sender);
    }
  }

  /**
   * @dev Withdraws ETH deposits after the cutoff date if the settlement wasn't executed.
   * @param settlementId The id of the settlement to withdraw ETH from.
   */
  function withdrawETH(uint256 settlementId) external nonReentrant {
    Settlement storage settlement = settlements[settlementId];
    if (settlement.flows.length == 0) revert SettlementDoesNotExist();
    if (block.timestamp <= settlement.cutoffDate) revert CutoffDateNotPassed();
    if (settlement.isSettled) revert SettlementAlreadyExecuted();
    if (settlement.ethDeposits[msg.sender] == 0) revert NoETHToWithdraw();

    uint256 amount = settlement.ethDeposits[msg.sender];
    settlement.ethDeposits[msg.sender] = 0;

    // sendValue reverts if unsuccessful
    Address.sendValue(payable(msg.sender), amount);
    emit ETHWithdrawn(msg.sender, amount);
  }

  /**
   * @dev Make explicit the intention to revert transaction if contract is directly sent Ether.
   */
  receive() external payable {
    revert CannotSendEtherDirectly();
  }

  //------------------------------------------------------------------------------
  // Internal
  //------------------------------------------------------------------------------
  /**
   * @dev Internal helper to get ETH required and deposited for a party.
   * @param settlement The settlement to check.
   * @param party The party to check.
   * @return etherRequired The total ETH required from the party.
   * @return etherDeposited The total ETH deposited by the party.
   */
  function _getPartyEthStats(
    Settlement storage settlement,
    address party
  ) internal view returns (uint256 etherRequired, uint256 etherDeposited) {
    uint256 lengthFlows = settlement.flows.length;
    for (uint256 i = 0; i < lengthFlows; i++) {
      Flow storage flow = settlement.flows[i];
      if (flow.from == party && flow.token == address(0)) {
        etherRequired += flow.amountOrId;
      }
    }
    etherDeposited = settlement.ethDeposits[party];
  }

  /**
   * @dev Internal helper to get TokenStatus for all tokens for a party.
   * NB: This function is not intended to be called inside a state-changing transaction, this view is for external callers
   * only, so gas consumption is not critical.
   * @param settlement The settlement to check.
   * @param party The party to check.
   * @return tokenStatuses An array of TokenStatus, one for each token in the settlement.
   */
  function _getTokenStatuses(
    Settlement storage settlement,
    address party
  ) internal view returns (TokenStatus[] memory) {
    uint256 lengthFlows = settlement.flows.length;
    TokenStatus[] memory tokenStatuses = new TokenStatus[](lengthFlows);
    uint256 index = 0;

    for (uint256 i = 0; i < lengthFlows; i++) {
      Flow storage f = settlement.flows[i];
      if (f.from != party || f.token == address(0)) continue;

      if (f.isNFT) {
        IERC721 nft = IERC721(f.token);
        tokenStatuses[index++] = TokenStatus({
          tokenAddress: f.token,
          isNFT: true,
          amountOrIdRequired: f.amountOrId,
          amountOrIdApprovedForDvp: nft.getApproved(f.amountOrId) == address(this) ||
            nft.isApprovedForAll(party, address(this))
            ? f.amountOrId
            : 0,
          amountOrIdHeldByParty: nft.ownerOf(f.amountOrId) == party ? f.amountOrId : 0
        });
      } else {
        uint256 allowed = IERC20(f.token).allowance(party, address(this));
        uint256 balance = IERC20(f.token).balanceOf(party);

        tokenStatuses[index++] = TokenStatus({
          tokenAddress: f.token,
          isNFT: false,
          amountOrIdRequired: f.amountOrId,
          amountOrIdApprovedForDvp: allowed,
          amountOrIdHeldByParty: balance
        });
      }
    }

    // Trim the array to fit actual entries
    assembly {
      mstore(tokenStatuses, index)
    }

    return tokenStatuses;
  }

  /**
   * @dev Internal version of {isERC721}
   */
  function _isERC721(address token) internal view returns (bool) {
    return token.supportsInterface(type(IERC721).interfaceId);
  }

  /**
   * @dev Internal version of {isERC20}
   */
  function _isERC20(address token) internal view returns (bool) {
    (bool success, bytes memory result) = token.staticcall(abi.encodeWithSelector(SELECTOR_ERC20_DECIMALS));
    return success && result.length == 32;
  }
}
