// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DeliveryVersusPaymentV1} from "../../../src/dvp/V1/DeliveryVersusPaymentV1.sol";
import {IDeliveryVersusPaymentV1} from "../../../src/dvp/V1/IDeliveryVersusPaymentV1.sol";
import "forge-std/Test.sol";

/**
 * @title DVPHandler
 * @dev Handler contract for guided fuzzing of the DeliveryVersusPaymentV1 contract
 *
 * - Manages multiple actors who can create, approve, and execute settlements
 * - Tracks settlement states and ensures realistic interactions
 * - Provides guided fuzzing by ensuring reasonable function call ordering
 * - Maintains ghost variables to track system-wide state for invariant checking
 *
 * Handler functions:
 * 1. createSettlement: Create a settlement with multiple flows (all ETH for now)
 * 2. approveSettlement: Parties deposit ETH and approve the settlement
 * 3. executeSettlement: Execute the settlement
 *
 * IMPORTANT:
 * All top level functions in this test contract are initially called by Forge fuzzer and given a msg.sender that is random.
 * Most top level functions use a "useActor" modifier that pranks the msg.sender to be one of the known actors (Alice, Bob etc).
 * However, a prank doesn't take effect until the NEXT EXTERNAL call. If you call an internal function from within this contract,
 * msg.sender will still be the fuzzed address, not the pranked actor. If you call an external function in this contract
 * using e.g. `this.function()`, then msg.sender will correctly be the pranked actor.
 */
contract DVPHandler is Test {
  DeliveryVersusPaymentV1 public dvp;

  // Actors
  address[] public actors;
  mapping(address => uint256) public ethBalances;

  // Mirror DVP contract state for invariant checking
  uint256[] public settlementIds;
  mapping(uint256 => bool) public settlementExecuted;
  mapping(uint256 => uint256) public settlementCutoffDate;
  mapping(uint256 => address[]) public settlementParties; // All parties involved in each settlement
  mapping(uint256 => mapping(address => bool)) public settlementApprovals; // Approval state per settlement per party
  mapping(uint256 => mapping(address => uint256)) public settlementEthDeposits; // ETH deposits per settlement per party

  // Track aggregate state for invariant verification
  uint256 public ghost_totalEthDeposited;
  uint256 public ghost_totalSettlementsCreated;
  uint256 public ghost_totalApprovalsByParty;
  uint256 public ghost_totalSettlementsExecuted;
  uint256 public ghost_totalSettlementsExecutedAuto; // Auto-settled settlements

  modifier useActor(uint256 actorIndexSeed) {
    require(actors.length > 0, "Actors array is empty");
    address currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
    vm.startPrank(currentActor);
    _;
    vm.stopPrank();
  }

  /// @dev Track function call statistics for debugging
  modifier countCall(string memory functionName) {
    bytes32 key = keccak256(abi.encodePacked(functionName));
    calls[key]++;
    _;
  }

  mapping(bytes32 => uint256) public calls;

  constructor(DeliveryVersusPaymentV1 _dvp) {
    dvp = _dvp;

    // Actor setup
    actors.push(makeAddr("Alice"));
    actors.push(makeAddr("Bob"));
    actors.push(makeAddr("Charlie"));
    actors.push(makeAddr("David"));
    for (uint256 i = 0; i < actors.length; i++) {
      vm.deal(actors[i], 100 ether);
      ethBalances[actors[i]] = 100 ether;
    }
  }

  /**
   * @dev Creates a new settlement with randomly generated flows.
   * msg.sender here is a fuzzer-chosen random address, not an actor, useActor only takes effect in external call.
   *
   * @param actorSeed Random seed to select which actor creates the settlement
   * @param flowCount Random seed for number of flows (bounded 1-5)
   * @param cutoffSeed Random seed for cutoff date (bounded 1 hour - 7 days)
   * @param isAutoSettled Whether settlement should auto-execute after final approval
   */
  function createSettlement(
    uint256 actorSeed,
    uint256 flowCount,
    uint256 cutoffSeed,
    bool isAutoSettled
  ) external useActor(actorSeed) countCall("createSettlement") {
    flowCount = bound(flowCount, 1, 5);
    uint256 cutoffDate = block.timestamp + bound(cutoffSeed, 3600, 86400 * 7); // 1 hour to 7 days

    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](flowCount);

    // Generate random flows
    for (uint256 i = 0; i < flowCount; i++) {
      flows[i] = _generateFlow(i);
    }

    try dvp.createSettlement(flows, "Test Settlement", cutoffDate, isAutoSettled) returns (uint256 settlementId) {
      // Update tracking to mirror the DVP contract state
      settlementIds.push(settlementId);
      settlementCutoffDate[settlementId] = cutoffDate;
      ghost_totalSettlementsCreated++;
      for (uint256 i = 0; i < flows.length; i++) {
        _addPartyToSettlement(settlementId, flows[i].from);
      }
    } catch {
      // Catch nothing, settlement creation failed (e.g., invalid flows), continue fuzzing
    }
  }

  /**
   * @dev Approves a settlement and deposits required ETH
   * msg.sender here is a fuzzer-chosen random address, not an actor, useActor only takes effect in external call.
   *
   * @param actorSeed Random seed to select which actor approves
   * @param settlementSeed Random seed to select which settlement to approve
   */
  function approveSettlement(
    uint256 actorSeed,
    uint256 settlementSeed
  ) external useActor(actorSeed) countCall("approveSettlement") {
    if (settlementIds.length == 0) return;

    // Pick random settlement from existing ones created so far
    uint256 settlementId = settlementIds[bound(settlementSeed, 0, settlementIds.length - 1)];
    if (settlementExecuted[settlementId]) return;

    // Calculate how much ETH the actor needs to deposit for their flows
    uint256 ethRequired = this.calculateEthRequiredForMsgSender(settlementId);

    // During approval, attach and send ETH if it's needed
    uint256[] memory ids = new uint256[](1);
    ids[0] = settlementId;
    try dvp.approveSettlements{value: ethRequired}(ids) {
      // Update tracking to mirror the DVP contract state
      this.updateTrackingApprovalByParty(settlementId, ethRequired);

      // Perhaps the settlement was also executed
      (, , , bool isSettled, bool isAutoSettled) = dvp.getSettlement(settlementId);
      if (isSettled && isAutoSettled) {
        this.updateTrackingExecuteSettlement(settlementId, true);
      }
    } catch {
      // Approve failed, catch nothing, do nothing
    }
  }

  /**
   * @dev Executes a settlement if all approvals are in place
   *
   * @param actorSeed Random seed to select which actor executes (anyone can execute)
   * @param settlementSeed Random seed to select which settlement to execute
   */
  function executeSettlement(
    uint256 actorSeed,
    uint256 settlementSeed
  ) external useActor(actorSeed) countCall("executeSettlement") {
    if (settlementIds.length == 0) return;

    uint256 settlementId = settlementIds[bound(settlementSeed, 0, settlementIds.length - 1)];
    if (settlementExecuted[settlementId]) return; // Can't execute twice

    try dvp.executeSettlement(settlementId) {
      this.updateTrackingExecuteSettlement(settlementId, false);
    } catch {
      // Execution failed (e.g., not all approved, past cutoff), continue fuzzing
    }
  }

  /// @dev Generates a random ETH flow for settlement creation
  function _generateFlow(uint256 seed) internal view returns (IDeliveryVersusPaymentV1.Flow memory) {
    address from = actors[bound(seed, 0, actors.length - 1)];
    address to = actors[bound(seed + 1, 0, actors.length - 1)];

    return
      IDeliveryVersusPaymentV1.Flow({
        token: address(0),
        isNFT: false,
        from: from,
        to: to,
        amountOrId: bound(seed, 0.1 ether, 10 ether)
      });
  }

  /// @dev Calculates ETH required for msg.sender to approve a settlement
  function calculateEthRequiredForMsgSender(uint256 settlementId) external view returns (uint256) {
    try dvp.getSettlement(settlementId) returns (
      string memory,
      uint256,
      IDeliveryVersusPaymentV1.Flow[] memory flows,
      bool,
      bool
    ) {
      uint256 ethRequired = 0;
      // Sum all ETH amounts this party is sending
      for (uint256 i = 0; i < flows.length; i++) {
        if (flows[i].from == msg.sender && flows[i].token == address(0)) {
          ethRequired += flows[i].amountOrId;
        }
      }
      return ethRequired;
    } catch {
      return 0; // Settlement doesn't exist or other error
    }
  }

  /// @dev Adds a party to the settlement's party list (ensure no duplicates)
  function _addPartyToSettlement(uint256 settlementId, address party) internal {
    address[] storage parties = settlementParties[settlementId];
    for (uint256 i = 0; i < parties.length; i++) {
      if (parties[i] == party) return;
    }
    parties.push(party);
  }

  /// @dev Update ghost variables when a settlement is approved
  function updateTrackingApprovalByParty(uint256 settlementId, uint256 ethRequired) external {
    settlementApprovals[settlementId][msg.sender] = true;
    settlementEthDeposits[settlementId][msg.sender] += ethRequired;
    ghost_totalEthDeposited += ethRequired;
    ghost_totalApprovalsByParty++;
    ethBalances[msg.sender] -= ethRequired;
  }

  /// @dev Update ghost variables when a settlement is executed
  function updateTrackingExecuteSettlement(uint256 settlementId, bool autoExecuted) external {
    settlementExecuted[settlementId] = true;
    if (autoExecuted) {
      ghost_totalSettlementsExecutedAuto++;
    } else {
      ghost_totalSettlementsExecuted++;
    }

    for (uint256 i = 0; i < settlementParties[settlementId].length; i++) {
      address party = settlementParties[settlementId][i];
      uint256 ethDeposit = settlementEthDeposits[settlementId][party];
      if (ethDeposit > 0) {
        ghost_totalEthDeposited -= ethDeposit;
        settlementEthDeposits[settlementId][party] = 0;
      }
    }
  }

  /// @dev Returns the total number of settlements created
  function getSettlementCount() external view returns (uint256) {
    return settlementIds.length;
  }

  /// @dev Returns the number of times a specific function was called during fuzzing
  function getCallCount(string memory functionName) public view returns (uint256) {
    return calls[keccak256(abi.encodePacked(functionName))];
  }

  /// @dev Print handler call summary for debugging
  function printCallSummary() external view {
    console.log("+------------------------------------------+");
    console.log("|  DVP Handler Call Summary for Last Run   |");
    console.log("+------------------------------------------+");
    console.log("Function calls:");
    console.log("  createSettlement calls:", getCallCount("createSettlement"));
    console.log("  approveSettlement calls:", getCallCount("approveSettlement"));
    console.log("  executeSettlement calls:", getCallCount("executeSettlement"));
    console.log("Settlement Counts:");
    console.log("  Total settlements created:", ghost_totalSettlementsCreated);
    console.log("  Total settlements auto-executed:", ghost_totalSettlementsExecutedAuto);
    console.log("  Total settlements executed:", ghost_totalSettlementsExecuted);
    console.log("Party Action Counts:");
    console.log("  Total party approvals:", ghost_totalApprovalsByParty);
    console.log("+------------------------------------------+");
  }
}
