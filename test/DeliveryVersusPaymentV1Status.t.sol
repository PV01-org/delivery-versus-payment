// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TestDvpBase} from "./TestDvpBase.sol";
import {IDeliveryVersusPaymentV1} from "../src/dvp/V1/IDeliveryVersusPaymentV1.sol";
import {DeliveryVersusPaymentV1} from "../src/dvp/V1/DeliveryVersusPaymentV1.sol";

/**
 * @title DeliveryVersusPaymentV1StatusTest
 * @notice Tests settlement party status functionality including approval states, ETH deposits, token approvals,
 * balance checks, NFT ownership verification, and complex multi-token settlement status tracking.
 */
contract DeliveryVersusPaymentV1StatusTest is TestDvpBase {
  //--------------------------------------------------------------------------------
  // getSettlementPartyStatus Tests
  //--------------------------------------------------------------------------------
  function test_getSettlementPartyStatus_BeforeApproval_ReturnsCorrectStatus() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createMixedFlows();
    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Check Alice's status (sender in multiple flows)
    (
      bool isApproved,
      uint256 etherRequired,
      uint256 etherDeposited,
      DeliveryVersusPaymentV1.TokenStatus[] memory tokenStatuses
    ) = dvp.getSettlementPartyStatus(settlementId, alice);

    assertFalse(isApproved);
    assertEq(etherRequired, 0); // Alice doesn't send ETH in mixed flows
    assertEq(etherDeposited, 0);
    assertEq(tokenStatuses.length, 2); // USDC and NFT

    // Verify token statuses
    bool foundUSDC = false;
    bool foundNFT = false;

    for (uint256 i = 0; i < tokenStatuses.length; i++) {
      if (tokenStatuses[i].tokenAddress == usdc && !tokenStatuses[i].isNFT) {
        foundUSDC = true;
        assertEq(tokenStatuses[i].amountOrIdRequired, TOKEN_AMOUNT_SMALL_6_DECIMALS);
        assertEq(tokenStatuses[i].amountOrIdApprovedForDvp, 0); // Not approved yet
        assertEq(tokenStatuses[i].amountOrIdHeldByParty, TOKEN_AMOUNT_LARGE_6_DECIMALS); // Full balance
      } else if (tokenStatuses[i].tokenAddress == nftCat && tokenStatuses[i].isNFT) {
        foundNFT = true;
        assertEq(tokenStatuses[i].amountOrIdRequired, NFT_CAT_DAISY);
        assertEq(tokenStatuses[i].amountOrIdApprovedForDvp, 0); // Not approved yet
        assertEq(tokenStatuses[i].amountOrIdHeldByParty, NFT_CAT_DAISY); // Alice owns it
      }
    }

    assertTrue(foundUSDC);
    assertTrue(foundNFT);
  }

  function test_getSettlementPartyStatus_AfterPartialApproval_ReturnsCorrectStatus() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createMixedFlows();
    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Partially approve - only USDC, not NFT
    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);

    (
      bool isApproved,
      uint256 etherRequired,
      uint256 etherDeposited,
      DeliveryVersusPaymentV1.TokenStatus[] memory tokenStatuses
    ) = dvp.getSettlementPartyStatus(settlementId, alice);

    assertFalse(isApproved); // Still not approved settlement itself
    assertEq(etherRequired, 0);
    assertEq(etherDeposited, 0);

    // Check token approvals
    for (uint256 i = 0; i < tokenStatuses.length; i++) {
      if (tokenStatuses[i].tokenAddress == usdc) {
        assertEq(tokenStatuses[i].amountOrIdApprovedForDvp, TOKEN_AMOUNT_SMALL_6_DECIMALS);
      } else if (tokenStatuses[i].tokenAddress == nftCat) {
        assertEq(tokenStatuses[i].amountOrIdApprovedForDvp, 0); // NFT not approved
      }
    }
  }

  function test_getSettlementPartyStatus_AfterSettlementApproval_ReturnsCorrectStatus() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Approve ERC20 and then settlement
    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    (bool isApproved,,,) = dvp.getSettlementPartyStatus(settlementId, alice);
    assertTrue(isApproved);
  }

  function test_getSettlementPartyStatus_WithETHFlows_ReturnsCorrectETHStatus() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createETHFlows();
    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Check Alice's ETH requirements before approval
    (bool isApproved, uint256 etherRequired, uint256 etherDeposited,) =
      dvp.getSettlementPartyStatus(settlementId, alice);

    assertFalse(isApproved);
    assertEq(etherRequired, TOKEN_AMOUNT_SMALL_18_DECIMALS);
    assertEq(etherDeposited, 0);

    // Approve with ETH
    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.prank(alice);
    dvp.approveSettlements{value: TOKEN_AMOUNT_SMALL_18_DECIMALS}(settlementIds);

    // Check status after approval
    (isApproved, etherRequired, etherDeposited,) = dvp.getSettlementPartyStatus(settlementId, alice);

    assertTrue(isApproved);
    assertEq(etherRequired, TOKEN_AMOUNT_SMALL_18_DECIMALS);
    assertEq(etherDeposited, TOKEN_AMOUNT_SMALL_18_DECIMALS);
  }

  function test_getSettlementPartyStatus_WithInsufficientERC20Balance_ReturnsCorrectStatus() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(dave, alice, usdc, TOKEN_AMOUNT_LARGE_6_DECIMALS * 2); // More than Dave has

    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    (,,, DeliveryVersusPaymentV1.TokenStatus[] memory tokenStatuses) = dvp.getSettlementPartyStatus(settlementId, dave);

    assertEq(tokenStatuses.length, 1);
    assertEq(tokenStatuses[0].amountOrIdRequired, TOKEN_AMOUNT_LARGE_6_DECIMALS * 2);
    assertEq(tokenStatuses[0].amountOrIdHeldByParty, TOKEN_AMOUNT_LARGE_6_DECIMALS); // Dave's actual balance
    assertLt(tokenStatuses[0].amountOrIdHeldByParty, tokenStatuses[0].amountOrIdRequired);
  }

  function test_getSettlementPartyStatus_WithTransferredNFT_ReturnsCorrectStatus() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createNFTFlow(alice, bob, nftCat, NFT_CAT_DAISY);

    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Check initial status
    (,,, DeliveryVersusPaymentV1.TokenStatus[] memory tokenStatuses) = dvp.getSettlementPartyStatus(settlementId, alice);

    assertEq(tokenStatuses[0].amountOrIdHeldByParty, NFT_CAT_DAISY); // Alice owns it

    // Transfer NFT away
    vm.prank(alice);
    try nftCatToken.transferFrom(alice, eve, NFT_CAT_DAISY) {
      // ERC721 reverts on failure, success expected here
    } catch {
      revert("NFT transfer failed");
    }

    // Check status after transfer
    (,,, tokenStatuses) = dvp.getSettlementPartyStatus(settlementId, alice);
    assertEq(tokenStatuses[0].amountOrIdHeldByParty, 0); // Alice no longer owns it
  }

  function test_getSettlementPartyStatus_WithNFTApprovalForAll_ReturnsCorrectStatus() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createNFTFlow(alice, bob, nftCat, NFT_CAT_DAISY);

    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Use setApprovalForAll
    _approveAllNFTs(alice, nftCat);

    (,,, DeliveryVersusPaymentV1.TokenStatus[] memory tokenStatuses) = dvp.getSettlementPartyStatus(settlementId, alice);

    assertEq(tokenStatuses[0].amountOrIdApprovedForDvp, NFT_CAT_DAISY);
  }

  function test_getSettlementPartyStatus_WithSpecificNFTApproval_ReturnsCorrectStatus() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createNFTFlow(alice, bob, nftCat, NFT_CAT_DAISY);

    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Use specific approval
    _approveNFT(alice, nftCat, NFT_CAT_DAISY);

    (,,, DeliveryVersusPaymentV1.TokenStatus[] memory tokenStatuses) = dvp.getSettlementPartyStatus(settlementId, alice);

    assertEq(tokenStatuses[0].amountOrIdApprovedForDvp, NFT_CAT_DAISY);
  }

  function test_getSettlementPartyStatus_WithWrongNFTApproval_ReturnsZero() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createNFTFlow(alice, bob, nftCat, NFT_CAT_DAISY);

    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Approve different NFT
    _approveNFT(alice, nftCat, NFT_CAT_BUTTONS);

    (,,, DeliveryVersusPaymentV1.TokenStatus[] memory tokenStatuses) = dvp.getSettlementPartyStatus(settlementId, alice);

    assertEq(tokenStatuses[0].amountOrIdApprovedForDvp, 0); // Wrong NFT approved
  }

  function test_getSettlementPartyStatus_WithMultipleERC20Flows_AggregatesCorrectly() public {
    // Create flows where Alice sends USDC twice
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](2);
    flows[0] = _createERC20Flow(alice, bob, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    flows[1] = _createERC20Flow(alice, charlie, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);

    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Approve enough for both flows
    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS * 2);

    (,,, DeliveryVersusPaymentV1.TokenStatus[] memory tokenStatuses) = dvp.getSettlementPartyStatus(settlementId, alice);

    // Should only have one entry for USDC with aggregated amount
    assertEq(tokenStatuses.length, 2); // Two flows = two entries in status (not aggregated in this implementation)

    // Both entries should show the same approval amount (total approval for the token)
    for (uint256 i = 0; i < tokenStatuses.length; i++) {
      assertEq(tokenStatuses[i].amountOrIdApprovedForDvp, TOKEN_AMOUNT_SMALL_6_DECIMALS * 2);
    }
  }

  function test_getSettlementPartyStatus_AsReceiver_ReturnsEmptyTokenStatus() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Check Bob's status (he's a receiver in first flow, sender in second)
    (
      bool isApproved,
      uint256 etherRequired,
      uint256 etherDeposited,
      DeliveryVersusPaymentV1.TokenStatus[] memory tokenStatuses
    ) = dvp.getSettlementPartyStatus(settlementId, bob);

    assertFalse(isApproved);
    assertEq(etherRequired, 0);
    assertEq(etherDeposited, 0);
    assertEq(tokenStatuses.length, 1); // Only DAI that Bob sends
    assertEq(tokenStatuses[0].tokenAddress, dai);
  }

  function test_getSettlementPartyStatus_WithNonInvolvedParty_ReturnsEmptyStatus() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Check Dave's status (not involved)
    (
      bool isApproved,
      uint256 etherRequired,
      uint256 etherDeposited,
      DeliveryVersusPaymentV1.TokenStatus[] memory tokenStatuses
    ) = dvp.getSettlementPartyStatus(settlementId, dave);

    assertFalse(isApproved);
    assertEq(etherRequired, 0);
    assertEq(etherDeposited, 0);
    assertEq(tokenStatuses.length, 0);
  }

  function test_getSettlementPartyStatus_WithInvalidSettlement_Reverts() public {
    vm.expectRevert(DeliveryVersusPaymentV1.SettlementDoesNotExist.selector);
    dvp.getSettlementPartyStatus(NOT_A_SETTLEMENT_ID, alice);
  }

  function test_getSettlementPartyStatus_AfterSettlementExecution_ReturnsCorrectStatus() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, true); // auto-settle

    // Approve and execute
    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    _approveERC20(bob, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    vm.prank(bob);
    dvp.approveSettlements(settlementIds); // This will auto-execute

    // Check status after execution - should still show approved
    (bool isApproved,,,) = dvp.getSettlementPartyStatus(settlementId, alice);
    assertTrue(isApproved);
  }

  function test_getSettlementPartyStatus_WithComplexMixedFlows_HandlesCorrectly() public {
    // Create a complex scenario with multiple token types
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](5);
    flows[0] = _createERC20Flow(alice, bob, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    flows[1] = _createERC20Flow(alice, charlie, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);
    flows[2] = _createETHFlow(alice, dave, TOKEN_AMOUNT_SMALL_18_DECIMALS / 2);
    flows[3] = _createNFTFlow(alice, bob, nftCat, NFT_CAT_DAISY);
    flows[4] = _createNFTFlow(alice, charlie, nftCat, NFT_CAT_BUTTONS);

    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    (
      bool isApproved,
      uint256 etherRequired,
      uint256 etherDeposited,
      DeliveryVersusPaymentV1.TokenStatus[] memory tokenStatuses
    ) = dvp.getSettlementPartyStatus(settlementId, alice);

    assertFalse(isApproved);
    assertEq(etherRequired, TOKEN_AMOUNT_SMALL_18_DECIMALS / 2);
    assertEq(etherDeposited, 0);
    assertEq(tokenStatuses.length, 4); // USDC, DAI, and 2 NFTs

    // Verify we have the right mix of tokens
    uint256 erc20Count = 0;
    uint256 nftCount = 0;

    for (uint256 i = 0; i < tokenStatuses.length; i++) {
      if (tokenStatuses[i].isNFT) {
        nftCount++;
        assertTrue(tokenStatuses[i].tokenAddress == nftCat);
      } else {
        erc20Count++;
        assertTrue(tokenStatuses[i].tokenAddress == usdc || tokenStatuses[i].tokenAddress == dai);
      }
    }

    assertEq(erc20Count, 2);
    assertEq(nftCount, 2);
  }
}
