// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts-v5-2-0/utils/ReentrancyGuard.sol";
import "../src/dvp/V1/DeliveryVersusPaymentV1.sol";
import "./TestDvpBase.sol";

/**
 * @title DeliveryVersusPaymentV1EdgeCasesTest
 * @notice Tests edge cases and error conditions including reentrancy protection, token transfer failures,
 * auto-settlement failures with malicious tokens, complex settlement party status scenarios, and large settlement handling.
 */
contract DeliveryVersusPaymentV1EdgeCasesTest is TestDvpBase {
  //--------------------------------------------------------------------------------
  // Reentrancy Tests
  //--------------------------------------------------------------------------------
  function test_autoApproveSettlement_WithReentrancy_Reverts() public {
    // Set up settlement with malicious actor receiving ETH for reentrancy attempt
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createETHFlow(alice, address(maliciousActor), 1 ether);
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, true);
    vm.deal(alice, 2 ether);

    // Set up malicious actor for reentrancy
    maliciousActor.setReentrancyMode(MaliciousActorDVP.ReentrancyMode.ApproveSettlement);
    maliciousActor.setTargetSettlementId(settlementId);

    // Summary: The approve settlement transaction succeeds, internally the execute part fails due to reentrancy attempt.
    // Detail: The approve settlement transaction triggers auto-execute, alice sends ETH to malicious actor contract.
    // The malicious actor contract's receive function makes a reentrant call to approveSettlements, which reverts,
    // gets trapped by the try{} clause in approveSettlements() and emits a log with info about the "internal revert".
    // The approval remains.
    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);
    vm.prank(alice);
    vm.expectEmit(true, true, true, true);
    emit DeliveryVersusPaymentV1.SettlementAutoExecutionFailedOther({
      settlementId: settlementId,
      executor: alice,
      lowLevelData: abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector)
    });
    dvp.approveSettlements{value: 1 ether}(settlementIds);

    // Approval should have stuck
    (bool isApproved, , , ) = dvp.getSettlementPartyStatus(settlementId, alice);
    assertTrue(isApproved);
  }

  function test_executeSettlement_WithReentrancy_Reverts() public {
    // Set up malicious actor for reentrancy attempt
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createETHFlow(alice, address(maliciousActor), 1 ether);
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);
    vm.deal(alice, 2 ether);

    // Set up malicious actor for reentrancy
    maliciousActor.setReentrancyMode(MaliciousActorDVP.ReentrancyMode.ExecuteSettlement);
    maliciousActor.setTargetSettlementId(settlementId);

    // Approve settlement
    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);
    vm.prank(alice);
    dvp.approveSettlements{value: 1 ether}(settlementIds);

    // Try to execute, here the maliciousActor contract receives ETH and attempts reentrancy
    vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
    dvp.executeSettlement(settlementId);
  }

  function test_revokeApprovals_WithReentrancy_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createETHFlow(address(maliciousActor), alice, 1 ether);

    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    vm.deal(address(maliciousActor), 2 ether);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    // Approve first
    vm.prank(address(maliciousActor));
    dvp.approveSettlements{value: 1 ether}(settlementIds);

    // Set up reentrancy for revoke
    maliciousActor.setReentrancyMode(MaliciousActorDVP.ReentrancyMode.RevokeApproval);
    maliciousActor.setTargetSettlementId(settlementId);

    // Try to revoke - should revert due to reentrancy guard
    vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
    vm.prank(address(maliciousActor));
    dvp.revokeApprovals(settlementIds);
  }

  function test_withdrawETH_WithReentrancy_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createETHFlow(address(maliciousActor), alice, 1 ether);

    uint256 cutoff = _getFutureTimestamp(1);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    vm.deal(address(maliciousActor), 2 ether);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    // Approve first
    vm.prank(address(maliciousActor));
    dvp.approveSettlements{value: 1 ether}(settlementIds);

    // Move past cutoff
    _advanceTime(2 days);

    // Set up reentrancy for withdrawETH
    maliciousActor.setReentrancyMode(MaliciousActorDVP.ReentrancyMode.WithdrawETH);
    maliciousActor.setTargetSettlementId(settlementId);

    // Try to withdraw - should revert due to reentrancy guard
    vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
    vm.prank(address(maliciousActor));
    dvp.withdrawETH(settlementId);
  }

  //--------------------------------------------------------------------------------
  // Token Transfer Failure Tests
  //--------------------------------------------------------------------------------
  function test_executeSettlement_WithERC20TransferFailureCustomError_Reverts() public {
    // Create flow with insufficient balance
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(dave, alice, usdc, TOKEN_AMOUNT_LARGE_6_DECIMALS);

    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Want Dave to not have enough USDC - drain his balance
    uint256 daveUsdcBalance = usdcToken.balanceOf(dave);
    vm.prank(dave);
    usdcToken.transfer(eve, daveUsdcBalance);

    // Approve
    _approveERC20(dave, usdc, TOKEN_AMOUNT_LARGE_6_DECIMALS);
    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);
    vm.prank(dave);
    dvp.approveSettlements(settlementIds);

    // Execution should fail due to insufficient balance
    vm.expectRevert(
      abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, dave, 0, TOKEN_AMOUNT_LARGE_6_DECIMALS)
    );
    dvp.executeSettlement(settlementId);
  }

  function test_executeSettlement_WithERC20AllowanceFailure_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);

    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Approve settlement but then revoke ERC20 allowance
    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    // Revoke ERC20 allowance after settlement approval
    vm.prank(alice);
    usdcToken.approve(address(dvp), 0);

    // Execution should fail due to insufficient allowance
    vm.expectRevert(
      abi.encodeWithSelector(
        IERC20Errors.ERC20InsufficientAllowance.selector,
        address(dvp),
        0,
        TOKEN_AMOUNT_SMALL_6_DECIMALS
      )
    );
    dvp.executeSettlement(settlementId);
  }

  function test_executeSettlement_WithNFTOwnershipFailure_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createNFTFlow(alice, bob, nftCat, NFT_CAT_DAISY);

    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Approve NFT and settlement
    _approveNFT(alice, nftCat, NFT_CAT_DAISY);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    // Transfer NFT away after approval
    vm.prank(alice);
    nftCatToken.transferFrom(alice, eve, NFT_CAT_DAISY);

    // Execution should fail as Alice no longer owns the NFT
    vm.expectRevert(
      abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(dvp), NFT_CAT_DAISY)
    );
    dvp.executeSettlement(settlementId);
  }

  function test_executeSettlement_WithNFTApprovalFailure_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createNFTFlow(alice, bob, nftCat, NFT_CAT_DAISY);

    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Approve NFT first
    _approveNFT(alice, nftCat, NFT_CAT_DAISY);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    // Revoke NFT approval after settlement approval
    vm.prank(alice);
    nftCatToken.approve(address(0), NFT_CAT_DAISY);

    // Execution should fail due to missing approval
    vm.expectRevert(
      abi.encodeWithSelector(IERC721Errors.ERC721InsufficientApproval.selector, address(dvp), NFT_CAT_DAISY)
    );
    dvp.executeSettlement(settlementId);
  }

  //--------------------------------------------------------------------------------
  // Auto-Settlement Failure Tests
  //--------------------------------------------------------------------------------
  function test_autoSettlement_WithERC20TransferFailure_EmitsFailureEvent() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(dave, alice, usdc, TOKEN_AMOUNT_LARGE_6_DECIMALS);

    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, true); // auto-settle

    // We want Dave to not have enough USDC
    uint256 daveUsdcBalance = usdcToken.balanceOf(dave);
    vm.prank(dave);
    usdcToken.transfer(eve, daveUsdcBalance);

    // Approve the transfer anyway
    _approveERC20(dave, usdc, TOKEN_AMOUNT_LARGE_6_DECIMALS);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    // Auto-settlement should fail but not revert the approval
    vm.expectEmit(true, true, false, false);
    emit DeliveryVersusPaymentV1.SettlementAutoExecutionFailedOther(settlementId, dave, "");

    vm.prank(dave);
    dvp.approveSettlements(settlementIds);

    // Settlement should be approved but not executed
    (, , , bool isSettled, ) = dvp.getSettlement(settlementId);
    assertFalse(isSettled);
    assertTrue(dvp.isSettlementApproved(settlementId));
  }

  function test_autoSettlement_WithMaliciousTokenReentrancy_EmitsFailureEvent() public {
    // Create settlement with malicious token that will try to re-enter
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, maliciousTokenAddress, 1000);

    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, true); // auto-settle

    // Set up malicious token for reentrancy
    maliciousToken.setTargetSettlementId(settlementId);

    // Approve malicious token
    vm.prank(alice);
    maliciousToken.approve(address(dvp), 1000);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    // Auto-settlement should fail due to reentrancy and emit failure event
    vm.expectEmit(true, true, false, false);
    emit DeliveryVersusPaymentV1.SettlementAutoExecutionFailedOther(settlementId, alice, "");

    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    // Settlement should be approved but not executed
    (, , , bool isSettled, ) = dvp.getSettlement(settlementId);
    assertFalse(isSettled);
    assertTrue(dvp.isSettlementApproved(settlementId));
  }

  //--------------------------------------------------------------------------------
  // getSettlementPartyStatus Tests
  //--------------------------------------------------------------------------------
  function test_getSettlementPartyStatus_WithComplexScenario_ReturnsCorrectStatus() public {
    // Create mixed flows involving Alice
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](4);
    flows[0] = _createERC20Flow(alice, bob, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    flows[1] = _createETHFlow(alice, charlie, TOKEN_AMOUNT_SMALL_18_DECIMALS);
    flows[2] = _createNFTFlow(alice, dave, nftCat, NFT_CAT_DAISY);
    flows[3] = _createERC20Flow(bob, alice, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Partially approve tokens
    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    _approveNFT(alice, nftCat, NFT_CAT_DAISY);
    // Don't approve the ERC20 for the full amount to test partial approval

    // Check Alice's status before approval
    (
      bool isApproved,
      uint256 etherRequired,
      uint256 etherDeposited,
      DeliveryVersusPaymentV1.TokenStatus[] memory tokenStatuses
    ) = dvp.getSettlementPartyStatus(settlementId, alice);

    assertFalse(isApproved);
    assertEq(etherRequired, TOKEN_AMOUNT_SMALL_18_DECIMALS);
    assertEq(etherDeposited, 0);
    assertEq(tokenStatuses.length, 2); // USDC and NFT that Alice sends

    // Check USDC status
    bool foundUSDC = false;
    bool foundNFT = false;
    for (uint256 i = 0; i < tokenStatuses.length; i++) {
      if (tokenStatuses[i].tokenAddress == usdc) {
        foundUSDC = true;
        assertEq(tokenStatuses[i].amountOrIdRequired, TOKEN_AMOUNT_SMALL_6_DECIMALS);
        assertEq(tokenStatuses[i].amountOrIdApprovedForDvp, TOKEN_AMOUNT_SMALL_6_DECIMALS);
        assertFalse(tokenStatuses[i].isNFT);
      } else if (tokenStatuses[i].tokenAddress == nftCat) {
        foundNFT = true;
        assertEq(tokenStatuses[i].amountOrIdRequired, NFT_CAT_DAISY);
        assertEq(tokenStatuses[i].amountOrIdApprovedForDvp, NFT_CAT_DAISY);
        assertTrue(tokenStatuses[i].isNFT);
      }
    }
    assertTrue(foundUSDC);
    assertTrue(foundNFT);
  }

  function test_getSettlementPartyStatus_WithNFTApprovalForAll_ReportsCorrectly() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createNFTFlow(alice, bob, nftCat, NFT_CAT_DAISY);

    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Use setApprovalForAll instead of individual approval
    _approveAllNFTs(alice, nftCat);

    (, , , DeliveryVersusPaymentV1.TokenStatus[] memory tokenStatuses) = dvp.getSettlementPartyStatus(
      settlementId,
      alice
    );

    assertEq(tokenStatuses.length, 1);
    assertEq(tokenStatuses[0].amountOrIdApprovedForDvp, NFT_CAT_DAISY);
    assertTrue(tokenStatuses[0].isNFT);
  }

  //--------------------------------------------------------------------------------
  // Large Settlement Tests
  //--------------------------------------------------------------------------------
  function test_createSettlement_WithManyFlows_Succeeds() public {
    // Create a settlement with many flows to test gas limits
    uint256 numFlows = 50;
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](numFlows);

    for (uint256 i = 0; i < numFlows; i++) {
      if (i % 4 == 0) {
        flows[i] = _createERC20Flow(alice, bob, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
      } else if (i % 4 == 1) {
        flows[i] = _createERC20Flow(bob, charlie, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);
      } else if (i % 4 == 2) {
        flows[i] = _createETHFlow(charlie, alice, TOKEN_AMOUNT_SMALL_18_DECIMALS / 100);
      } else {
        flows[i] = _createERC20Flow(charlie, dave, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
      }
    }

    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, "Large Settlement", cutoff, false);

    (, , IDeliveryVersusPaymentV1.Flow[] memory retrievedFlows, , ) = dvp.getSettlement(settlementId);
    assertEq(retrievedFlows.length, numFlows);
  }

  function test_approveSettlements_WithManySettlements_Succeeds() public {
    // Create multiple settlements and approve them all at once
    uint256 numSettlements = 10;
    uint256[] memory settlementIds = new uint256[](numSettlements);

    for (uint256 i = 0; i < numSettlements; i++) {
      IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
      flows[0] = _createERC20Flow(alice, bob, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);

      uint256 cutoff = _getFutureTimestamp(7 days);
      settlementIds[i] = dvp.createSettlement(flows, string(abi.encodePacked("Settlement ", i)), cutoff, false);
    }

    // Approve all ERC20 transfers at once
    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS * numSettlements);

    // Approve all settlements
    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    // Verify all are approved
    for (uint256 i = 0; i < numSettlements; i++) {
      (bool isApproved, , , ) = dvp.getSettlementPartyStatus(settlementIds[i], alice);
      assertTrue(isApproved);
    }
  }

  //--------------------------------------------------------------------------------
  // Zero Amount Edge Cases
  //--------------------------------------------------------------------------------
  function test_createSettlement_WithZeroAmountERC20_Succeeds() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, 0);

    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    assertEq(dvp.settlementIdCounter(), settlementId);
  }

  function test_createSettlement_WithZeroAmountETH_Succeeds() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createETHFlow(alice, bob, 0);

    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    assertEq(dvp.settlementIdCounter(), settlementId);
  }
}
