// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./TestDvpBase.sol";
import "../src/dvp/V1/DeliveryVersusPaymentV1.sol";

/**
 * @title DeliveryVersusPaymentV1CoreTest
 * @notice Tests core DVP functionality including settlement creation with various flow types, settlement retrieval,
 * approval status checking, token type detection (ERC20/ERC721), and direct ETH transfer restrictions.
 */
contract DeliveryVersusPaymentV1CoreTest is TestDvpBase {
  //--------------------------------------------------------------------------------
  // createSettlement Tests
  //--------------------------------------------------------------------------------
  function test_createSettlement_WithValidFlowsAndFutureCutoff_Succeeds() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createMixedFlows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    string memory refInput = _ref("create");

    vm.expectEmit(true, true, false, true);
    emit DeliveryVersusPaymentV1.SettlementCreated(1, address(this));

    //    vm.prank(creator);
    uint256 settlementId = dvp.createSettlement(flows, refInput, cutoff, false);

    assertEq(settlementId, 1);
    assertEq(dvp.settlementIdCounter(), 1);

    // Verify settlement details
    (
      string memory ref,
      uint256 cutoffDate,
      IDeliveryVersusPaymentV1.Flow[] memory retrievedFlows,
      IDeliveryVersusPaymentV1.Flow[] memory emptyNettedFlows,
      address creatorAddress,
      bool isSettled,
      bool isAutoSettled,
      bool useNettingOff
    ) = dvp.getSettlement(settlementId);

    assertEq(creatorAddress, address(this));
    assertEq(ref, refInput);
    assertEq(cutoffDate, cutoff);
    assertEq(retrievedFlows.length, flows.length);
    assertEq(emptyNettedFlows.length, 0);
    assertFalse(isSettled);
    assertFalse(isAutoSettled);
    assertFalse(useNettingOff);
  }

  function test_createSettlement_WithAutoSettlement_Succeeds() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(7 days);

    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, true);

    (,,,,, bool isSettled, bool isAutoSettled,) = dvp.getSettlement(settlementId);
    assertFalse(isSettled);
    assertTrue(isAutoSettled);
  }

  function test_createSettlement_WithNettedFlows_Succeeds() public {
    (
      IDeliveryVersusPaymentV1.Flow[] memory flows,
      IDeliveryVersusPaymentV1.Flow[] memory nettedFlows,
      uint256 cutoff,,,
    ) = _createMixedFlowsForNetting();

    uint256 settlementId = dvp.createSettlement(flows, nettedFlows, SETTLEMENT_REF, cutoff, true);

    (
      ,,,
      IDeliveryVersusPaymentV1.Flow[] memory retrievedNettedFlows,,
      bool isSettled,
      bool isAutoSettled,
      bool useNettingOff
    ) = dvp.getSettlement(settlementId);

    assertEq(nettedFlows.length, retrievedNettedFlows.length);
    assertFalse(isSettled);
    assertTrue(isAutoSettled);
    assertTrue(useNettingOff);
  }

  function test_createSettlement_WithValidEmptyNettedFlows_Succeeds() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](2);
    flows[0] = _createERC20Flow(alice, bob, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    flows[1] = _createERC20Flow(bob, alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    IDeliveryVersusPaymentV1.Flow[] memory emptyFlows = new IDeliveryVersusPaymentV1.Flow[](0);

    uint256 cutoff = _getFutureTimestamp(7 days);

    uint256 settlementId = dvp.createSettlement(flows, emptyFlows, SETTLEMENT_REF, cutoff, true);

    (
      ,,,
      IDeliveryVersusPaymentV1.Flow[] memory retrievedNettedFlows,,
      bool isSettled,
      bool isAutoSettled,
      bool useNettingOff
    ) = dvp.getSettlement(settlementId);
    assertEq(retrievedNettedFlows.length, 0);
    assertFalse(isSettled);
    assertTrue(isAutoSettled);
    assertTrue(useNettingOff);
  }

  function test_createSettlement_WithEmptyFlows_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory emptyFlows = new IDeliveryVersusPaymentV1.Flow[](0);
    uint256 cutoff = _getFutureTimestamp(7 days);

    vm.expectRevert(DeliveryVersusPaymentV1.NoFlowsProvided.selector);
    dvp.createSettlement(emptyFlows, SETTLEMENT_REF, cutoff, false);
  }

  function test_createSettlement_WithPastCutoff_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();

    // Move time forward first, then use current time - 1 to ensure past cutoff
    vm.warp(block.timestamp + 1 hours);
    uint256 pastCutoff = block.timestamp - 1;

    vm.expectRevert(DeliveryVersusPaymentV1.CutoffDatePassed.selector);
    dvp.createSettlement(flows, SETTLEMENT_REF, pastCutoff, false);
  }

  function test_createSettlement_WithInvalidNFTToken_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = IDeliveryVersusPaymentV1.Flow({
      token: usdc, // ERC20 token marked as NFT
      isNFT: true,
      from: alice,
      to: bob,
      amountOrId: 1
    });

    uint256 cutoff = _getFutureTimestamp(7 days);

    vm.expectRevert(DeliveryVersusPaymentV1.InvalidERC721Token.selector);
    dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);
  }

  function test_createSettlement_WithInvalidERC20Token_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = IDeliveryVersusPaymentV1.Flow({
      token: address(sanctionsList), // Non-ERC20 contract
      isNFT: false,
      from: alice,
      to: bob,
      amountOrId: 1000
    });

    uint256 cutoff = _getFutureTimestamp(7 days);

    vm.expectRevert(DeliveryVersusPaymentV1.InvalidERC20Token.selector);
    dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);
  }

  function test_createSettlement_UnknownPartyInNettedFlow_Reverts() public {
    // Original: Alice->Bob 100 USDC
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, 100);
    // Netted with unknown party (Dave)
    IDeliveryVersusPaymentV1.Flow[] memory netted = new IDeliveryVersusPaymentV1.Flow[](1);
    netted[0] = _createERC20Flow(alice, dave, usdc, 100);
    vm.expectRevert(DeliveryVersusPaymentV1.UnknownPartyInNettedFlow.selector);
    dvp.createSettlement(flows, netted, _ref("unknown_party"), _getFutureTimestamp(3 days), false);
  }

  function test_createSettlement_UnknownAssetInNettedFlow_Reverts() public {
    // Original: Alice->Bob 100 USDC
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, 100);

    // Netted with unknown asset (USDT instead of USDC)
    IDeliveryVersusPaymentV1.Flow[] memory netted = new IDeliveryVersusPaymentV1.Flow[](1);
    // Use USDT which is not in original assets for this settlement
    netted[0] = _createERC20Flow(alice, bob, usdt, 100);

    vm.expectRevert(DeliveryVersusPaymentV1.UnknownAssetInNettedFlow.selector);
    dvp.createSettlement(flows, netted, _ref("unknown_asset"), _getFutureTimestamp(3 days), false);
  }

  function test_createSettlement_ZeroNettedAmount_Reverts() public {
    // Original: Alice->Bob 100 USDC
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, 100);

    // Netted: Alice->Bob 0 USDC
    IDeliveryVersusPaymentV1.Flow[] memory netted = new IDeliveryVersusPaymentV1.Flow[](1);
    netted[0] = _createERC20Flow(alice, bob, usdc, 0);

    vm.expectRevert(DeliveryVersusPaymentV1.ZeroNettedAmountOrId.selector);
    dvp.createSettlement(flows, netted, _ref("zero_amt"), _getFutureTimestamp(3 days), false);
  }

  function test_createSettlement_ZeroIdNFT_Succeeds() public {
    // Original: Alice->Bob Cat (id=0)
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createNFTFlow(alice, bob, nftCat, 0);

    // Netted: Alice->Bob Cat (id=0)
    IDeliveryVersusPaymentV1.Flow[] memory netted = new IDeliveryVersusPaymentV1.Flow[](1);
    netted[0] = _createNFTFlow(alice, bob, nftCat, 0);

    uint256 settlementId = dvp.createSettlement(flows, netted, _ref("zero_nft_id"), _getFutureTimestamp(3 days), false);

    (
      ,,
      IDeliveryVersusPaymentV1.Flow[] memory retrievedFlows,
      IDeliveryVersusPaymentV1.Flow[] memory retrievedNettedFlows,,,,
    ) = dvp.getSettlement(settlementId);
    assertEq(retrievedFlows.length, 1);
    assertEq(retrievedNettedFlows.length, 1);
    assertEq(retrievedFlows[0].amountOrId, 0);
    assertEq(retrievedNettedFlows[0].amountOrId, 0);
  }

  function test_createSettlement_BalanceMismatch_Reverts() public {
    // Original: Alice->Bob 100 USDC
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, 100);

    // Netted: Alice->Bob 50 USDC
    IDeliveryVersusPaymentV1.Flow[] memory netted = new IDeliveryVersusPaymentV1.Flow[](1);
    netted[0] = _createERC20Flow(alice, bob, usdc, 50);

    vm.expectRevert(DeliveryVersusPaymentV1.NotEquivalentNettedFlows.selector);
    dvp.createSettlement(flows, netted, _ref("bal_mismatch"), _getFutureTimestamp(3 days), false);
  }

  function test_createSettlement_BalanceMismatchEmpty_Reverts() public {
    // Original: Alice->Bob 100 USDC
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, 100);
    // No netted flows
    IDeliveryVersusPaymentV1.Flow[] memory netted = new IDeliveryVersusPaymentV1.Flow[](0);
    uint256 cutoff = _getFutureTimestamp(7 days);

    vm.expectRevert(DeliveryVersusPaymentV1.NotEquivalentNettedFlows.selector);
    dvp.createSettlement(flows, netted, _ref("empty_netted"), cutoff, false);
  }

  function test_createSettlement_NFTAssetMustMatchTokenId() public {
    // Original: Alice -> Bob Daisy (id=1)
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createNFTFlow(alice, bob, nftCat, NFT_CAT_DAISY);

    IDeliveryVersusPaymentV1.Flow[] memory netted = new IDeliveryVersusPaymentV1.Flow[](1);
    netted[0] = _createNFTFlow(alice, bob, nftCat, NFT_CAT_BUTTONS);

    vm.expectRevert(DeliveryVersusPaymentV1.UnknownAssetInNettedFlow.selector);
    dvp.createSettlement(flows, netted, _ref("nft_key"), _getFutureTimestamp(3 days), false);
  }

  //--------------------------------------------------------------------------------
  // getSettlement Tests
  //--------------------------------------------------------------------------------
  function test_getSettlement_WithValidId_ReturnsCorrectDetails() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createMixedFlows();
    uint256 cutoff = _getFutureTimestamp(7 days);

    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, true);

    (
      string memory ref,
      uint256 cutoffDate,
      IDeliveryVersusPaymentV1.Flow[] memory retrievedFlows,
      IDeliveryVersusPaymentV1.Flow[] memory retrievedNettedFlows,
      address creatorAddress,
      bool isSettled,
      bool isAutoSettled,
      bool useNettingOff
    ) = dvp.getSettlement(settlementId);

    assertEq(ref, SETTLEMENT_REF);
    assertEq(cutoffDate, cutoff);
    assertEq(retrievedFlows.length, 4);
    assertEq(retrievedNettedFlows.length, 0);
    assertEq(creatorAddress, address(this));
    assertFalse(isSettled);
    assertTrue(isAutoSettled);
    assertFalse(useNettingOff);

    // Verify first flow details
    assertEq(retrievedFlows[0].token, usdc);
    assertEq(retrievedFlows[0].from, alice);
    assertEq(retrievedFlows[0].to, bob);
    assertFalse(retrievedFlows[0].isNFT);
    assertEq(retrievedFlows[0].amountOrId, TOKEN_AMOUNT_SMALL_6_DECIMALS);
  }

  function test_getSettlement_WithInvalidId_Reverts() public {
    vm.expectRevert(DeliveryVersusPaymentV1.SettlementDoesNotExist.selector);
    dvp.getSettlement(NOT_A_SETTLEMENT_ID);
  }

  //--------------------------------------------------------------------------------
  // isSettlementApproved Tests
  //--------------------------------------------------------------------------------
  function test_isSettlementApproved_WithNoApprovals_ReturnsFalse() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    assertFalse(dvp.isSettlementApproved(settlementId));
  }

  function test_isSettlementApproved_WithPartialApprovals_ReturnsFalse() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Approve ERC20 transfers
    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    _approveERC20(bob, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    // Only Alice approves
    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);
    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    assertFalse(dvp.isSettlementApproved(settlementId));
  }

  function test_isSettlementApproved_WithAllApprovals_ReturnsTrue() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Approve ERC20 transfers
    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    _approveERC20(bob, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    // Both parties approve
    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    vm.prank(bob);
    dvp.approveSettlements(settlementIds);

    assertTrue(dvp.isSettlementApproved(settlementId));
  }

  function test_isSettlementApproved_WithInvalidId_Reverts() public {
    vm.expectRevert(DeliveryVersusPaymentV1.SettlementDoesNotExist.selector);
    dvp.isSettlementApproved(NOT_A_SETTLEMENT_ID);
  }

  //--------------------------------------------------------------------------------
  // Token Detection Tests
  //--------------------------------------------------------------------------------
  function test_isERC721_WithERC721Token_ReturnsTrue() public view {
    assertTrue(dvp.isERC721(nftCat));
    assertTrue(dvp.isERC721(nftDog));
  }

  function test_isERC721_WithERC20Token_ReturnsFalse() public view {
    assertFalse(dvp.isERC721(usdc));
    assertFalse(dvp.isERC721(dai));
  }

  function test_isERC721_WithZeroAddress_ReturnsFalse() public view {
    assertFalse(dvp.isERC721(address(0)));
  }

  function test_isERC721_WithNonTokenContract_ReturnsFalse() public view {
    assertFalse(dvp.isERC721(address(sanctionsList)));
  }

  function test_isERC20_WithERC20Token_ReturnsTrue() public view {
    assertTrue(dvp.isERC20(usdc));
    assertTrue(dvp.isERC20(dai));
  }

  function test_isERC20_WithERC721Token_ReturnsFalse() public view {
    assertFalse(dvp.isERC20(nftCat));
    assertFalse(dvp.isERC20(nftDog));
  }

  function test_isERC20_WithZeroAddress_ReturnsFalse() public view {
    assertFalse(dvp.isERC20(address(0)));
  }

  function test_isERC20_WithNonTokenContract_ReturnsFalse() public view {
    assertFalse(dvp.isERC20(address(sanctionsList)));
  }

  //--------------------------------------------------------------------------------
  // Receive Function Tests
  //--------------------------------------------------------------------------------
  function test_receive_WithDirectETHTransfer_Reverts() public {
    vm.expectRevert(DeliveryVersusPaymentV1.CannotSendEtherDirectly.selector);
    payable(address(dvp)).transfer(1 ether);
  }
}
