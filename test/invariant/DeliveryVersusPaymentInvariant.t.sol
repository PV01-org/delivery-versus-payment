// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeliveryVersusPaymentV1} from "../../src/dvp/V1/DeliveryVersusPaymentV1.sol";
import {IDeliveryVersusPaymentV1} from "../../src/dvp/V1/IDeliveryVersusPaymentV1.sol";
import {DVPHandler} from "./handlers/DVPHandler.sol";

/**
 * @title DeliveryVersusPaymentInvariant
 * @dev Invariant tests for the DeliveryVersusPaymentV1 contract using guided fuzzing
 *
 * Handler ensures realistic function call ordering and maintains ghost variables
 * to track system state for invariant verification.
 *
 * Initial scope is limited to ETH flows: create, approve (with auto-execute) and execute settlements.
 *
 * A single invariant test performs all constraint checks.
 */
contract DeliveryVersusPaymentInvariant is StdInvariant, Test {
  DeliveryVersusPaymentV1 public dvp;
  DVPHandler public handler;

  function setUp() public {
    dvp = new DeliveryVersusPaymentV1();
    handler = new DVPHandler(dvp);

    // Register handler and its functions
    targetContract(address(handler));
    bytes4[] memory selectors = new bytes4[](3);
    selectors[0] = DVPHandler.createSettlementEth.selector;
    selectors[1] = DVPHandler.approveSettlementEth.selector;
    selectors[2] = DVPHandler.executeSettlement.selector;
    targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
  }

  /// @dev Settlement IDs must be monotonically increasing
  function constraint_settlementId_monotonic() public view {
    uint256 currentCounter = dvp.settlementIdCounter();
    uint256 totalCreated = handler.ghost_totalSettlementsCreated();
    assertEq(currentCounter, totalCreated, "Settlement ID counter should be == total settlements created");
  }

  /// @dev Contract ETH balance should equal sum of all deposits
  function constraint_eth_balance_consistency() public view {
    uint256 contractBalance = address(dvp).balance;
    uint256 totalDeposited = handler.ghost_totalEthDeposited();
    assertEq(contractBalance, totalDeposited, "Contract ETH balance should equal total deposited");
  }

  /// @dev Total settlements executed should not exceed total created
  function constraint_execution_count_bounds() public view {
    uint256 totalCreated = handler.ghost_totalSettlementsCreated();
    uint256 totalExecuted = handler.ghost_totalSettlementsExecuted();
    uint256 totalExecutedAuto = handler.ghost_totalSettlementsExecutedAuto();
    assertLe(
      totalExecuted + totalExecutedAuto, totalCreated, "Executed settlements should not exceed created settlements"
    );
  }

  /// @dev Get detailed ghost state information
  function getInvariantState()
    external
    view
    returns (
      uint256 contractBalance,
      uint256 ghostTotalDeposited,
      uint256 totalSettlements,
      uint256 totalExecuted,
      uint256 settlementCounter
    )
  {
    contractBalance = address(dvp).balance;
    ghostTotalDeposited = handler.ghost_totalEthDeposited();
    totalSettlements = handler.ghost_totalSettlementsCreated();
    totalExecuted = handler.ghost_totalSettlementsExecuted();
    settlementCounter = dvp.settlementIdCounter();
  }

  /// @dev Check if a specific settlement exists and get its details
  function getSettlementDetails(uint256 settlementId)
    external
    view
    returns (bool exists, bool isSettled, uint256 flowCount, uint256 cutoffDate)
  {
    try dvp.getSettlement(settlementId) returns (
      string memory, uint256 _cutoffDate, IDeliveryVersusPaymentV1.Flow[] memory flows, bool _isSettled, bool
    ) {
      exists = true;
      isSettled = _isSettled;
      flowCount = flows.length;
      cutoffDate = _cutoffDate;
    } catch {
      exists = false;
    }
  }

  /// @dev Main invariant function that checks all constraints
  function invariant_all() public view {
    constraint_eth_balance_consistency();
    constraint_settlementId_monotonic();
    constraint_execution_count_bounds();
    handler.printCallSummary();
  }
}
