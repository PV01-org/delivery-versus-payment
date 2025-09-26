// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./TestDvpBase.sol";
import "../src/dvp/V1/DeliveryVersusPaymentV1.sol";
import {IDeliveryVersusPaymentV1 as ICore} from "../src/dvp/V1/IDeliveryVersusPaymentV1.sol";

/**
 * @title DeliveryVersusPaymentV1NettedTest
 * @notice Extensive tests for executeSettlementNetted covering success paths, validation, refunds, and error cases.
 */
contract DeliveryVersusPaymentV1NettedTest is TestDvpBase {
  //--------------------------------------------------------------------------------
  // Helpers specific to these tests
  //--------------------------------------------------------------------------------
  function _createMixedFlowsForNetting()
    internal
    view
    returns (ICore.Flow[] memory flows, uint256 cutoff, uint256 ethA, uint256 ethB, uint256 ethC)
  {
    // Original flows (6 total):
    // ETH:  A->B 10e18, B->C 4e18, C->A 3e18
    // USDC: A->C 50,      C->B 20
    // NFT:  A->C Cat Daisy (id=1)
    flows = new ICore.Flow[](6);
    uint256 tenEth = TOKEN_AMOUNT_SMALL_18_DECIMALS; // 40e18 from base, but we want explicit 10e18 here.
    // Adjust: Use fixed values for clarity
    tenEth = 10 ether;

    flows[0] = _createETHFlow(alice, bob, tenEth);
    flows[1] = _createETHFlow(bob, charlie, 4 ether);
    flows[2] = _createETHFlow(charlie, alice, 3 ether);

    flows[3] = _createERC20Flow(alice, charlie, usdc, 50);
    flows[4] = _createERC20Flow(charlie, bob, usdc, 20);

    flows[5] = _createNFTFlow(alice, charlie, nftCat, NFT_CAT_DAISY);

    cutoff = _getFutureTimestamp(7 days);

    // ETH deposits required per original
    ethA = 7 ether; // A must deposit 7 ether
    ethB = 0 ether; // B must deposit 0 ether
    ethC = 0 ether; // C must deposit 0 ether
  }

  function _approveAllForMixedFlows(uint256 settlementId) internal {
    // ERC20 approvals
    _approveERC20(alice, usdc, 50);
    _approveERC20(charlie, usdc, 20);

    // NFT approval
    _approveNFT(alice, nftCat, NFT_CAT_DAISY);

    // Approvals (include ETH deposits)
    uint256[] memory ids = _getSettlementIdArray(settlementId);

    // Alice approves (no ETH auto-compute helper; send explicit amount from flows)
    vm.prank(alice);
    dvp.approveSettlements(ids); // Alice has no ETH in these helper flows? For mixed netting we will call a variant in tests.
  }

  //--------------------------------------------------------------------------------
  // Success path tests
  //--------------------------------------------------------------------------------
  function test_executeSettlementNetted_MixedAssets_EquivalentAndRefundsETH() public {
    // Arrange
    (ICore.Flow[] memory flows, uint256 cutoff, uint256 ethA, uint256 ethB, uint256 ethC) = _createMixedFlowsForNetting();
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false, true);

    // Approvals and deposits/allowances
    _approveERC20(alice, usdc, 50);
    _approveERC20(charlie, usdc, 20);
    _approveNFT(alice, nftCat, NFT_CAT_DAISY);

    uint256[] memory ids = _getSettlementIdArray(settlementId);

    // Alice approves with required ETH deposit
    vm.prank(alice);
    dvp.approveSettlements{value: ethA}(ids);

    vm.prank(bob);
    dvp.approveSettlements{value: ethB}(ids);

    vm.prank(charlie);
    dvp.approveSettlements{value: ethC}(ids);

    assertTrue(dvp.isSettlementApproved(settlementId));

    // Build netted flows (equivalent):
    // ETH nets to: A->C 7, B->C 4
    // USDC nets to: A->B 20, A->C 30
    // NFT unchanged: A->C Daisy
    ICore.Flow[] memory netted = new ICore.Flow[](5);
    netted[0] = _createETHFlow(alice, bob, 6 ether);
    netted[1] = _createETHFlow(alice, charlie, 1 ether);
    netted[2] = _createERC20Flow(alice, bob, usdc, 20);
    netted[3] = _createERC20Flow(alice, charlie, usdc, 30);
    netted[4] = _createNFTFlow(alice, charlie, nftCat, NFT_CAT_DAISY);

    // Snapshot balances for assertions
    uint256 aliceUSDCBefore = AssetToken(usdc).balanceOf(alice);
    uint256 bobUSDCBefore = AssetToken(usdc).balanceOf(bob);
    uint256 charlieUSDCBefore = AssetToken(usdc).balanceOf(charlie);
    address prevOwnerDaisy = NFT(nftCat).ownerOf(NFT_CAT_DAISY);

    // Act
    dvp.executeSettlementNetted(settlementId, netted);

    // Assert ERC20 balances changed as expected
    assertEq(AssetToken(usdc).balanceOf(alice), aliceUSDCBefore - 50, "Alice USDC decreased by 50");
    assertEq(AssetToken(usdc).balanceOf(bob), bobUSDCBefore + 20, "Bob USDC increased by 20");
    assertEq(AssetToken(usdc).balanceOf(charlie), charlieUSDCBefore + 30, "Charlie USDC increased by 30");

    // Assert NFT ownership moved to Charlie
    assertEq(prevOwnerDaisy, alice, "Precondition: Alice owned Daisy");
    assertEq(NFT(nftCat).ownerOf(NFT_CAT_DAISY), charlie, "Daisy transferred to Charlie");

    // Deposits refunded for all parties (0 after execution)
    (bool isApprovedA, uint256 ethReqA, uint256 ethDepA,) = dvp.getSettlementPartyStatus(settlementId, alice);
    (bool isApprovedB, uint256 ethReqB, uint256 ethDepB,) = dvp.getSettlementPartyStatus(settlementId, bob);
    (bool isApprovedC, uint256 ethReqC, uint256 ethDepC,) = dvp.getSettlementPartyStatus(settlementId, charlie);

    assertTrue(isApprovedA && isApprovedB && isApprovedC);
    assertEq(ethReqA, ethA);
    assertEq(ethReqB, ethB);
    assertEq(ethReqC, ethC);
    assertEq(ethDepA, 0);
    assertEq(ethDepB, 0);
    assertEq(ethDepC, 0);

    // isSettled
    (, , , bool isSettled, ) = dvp.getSettlement(settlementId);
    assertTrue(isSettled);
  }

  //--------------------------------------------------------------------------------
  // Revert: not approved
  //--------------------------------------------------------------------------------
  function test_executeSettlementNetted_NotApproved_Reverts() public {
    // Arrange: simple ERC20-only to avoid ETH deposits
    ICore.Flow[] memory flows = new ICore.Flow[](2);
    flows[0] = _createERC20Flow(alice, bob, usdc, 100);
    flows[1] = _createERC20Flow(bob, charlie, usdc, 50);
    uint256 settlementId = dvp.createSettlement(flows, _ref("notapproved"), _getFutureTimestamp(3 days), false, true);

    // Only Alice approves; Bob does not
    _approveERC20(alice, usdc, 100);
    uint256[] memory ids = _getSettlementIdArray(settlementId);

    vm.prank(alice);
    dvp.approveSettlements(ids);

    // Netted (valid) but should fail due to approval check
    ICore.Flow[] memory netted = new ICore.Flow[](2);
    netted[0] = _createERC20Flow(alice, charlie, usdc, 50);
    netted[1] = _createERC20Flow(alice, bob, usdc, 50);

    vm.expectRevert(DeliveryVersusPaymentV1.SettlementNotApproved.selector);
    dvp.executeSettlementNetted(settlementId, netted);
  }

  //--------------------------------------------------------------------------------
  // Revert: does not exist / cutoff passed / already executed / netoff disabled
  //--------------------------------------------------------------------------------
  function test_executeSettlementNetted_DoesNotExist_Reverts() public {
    ICore.Flow[] memory empty;
    vm.expectRevert(DeliveryVersusPaymentV1.SettlementDoesNotExist.selector);
    dvp.executeSettlementNetted(999, empty);
  }

  function test_executeSettlementNetted_CutoffPassed_Reverts() public {
    ICore.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(1);
    uint256 settlementId = dvp.createSettlement(flows, _ref("cutoff"), cutoff, false, true);

    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    _approveERC20(bob, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    uint256[] memory ids = _getSettlementIdArray(settlementId);
    vm.prank(alice);
    dvp.approveSettlements(ids);
    vm.prank(bob);
    dvp.approveSettlements(ids);

    // Move past cutoff
    _advanceTime(2);

    ICore.Flow[] memory netted = new ICore.Flow[](2);
    netted[0] = _createERC20Flow(alice, charlie, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    netted[1] = _createERC20Flow(bob, alice, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    vm.expectRevert(DeliveryVersusPaymentV1.CutoffDatePassed.selector);
    dvp.executeSettlementNetted(settlementId, netted);
  }

  function test_executeSettlementNetted_AlreadyExecuted_Reverts() public {
    ICore.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, _ref("exec_twice"), cutoff, false, true);

    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    _approveERC20(bob, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    uint256[] memory ids = _getSettlementIdArray(settlementId);
    vm.prank(alice);
    dvp.approveSettlements(ids);
    vm.prank(bob);
    dvp.approveSettlements(ids);

    // Valid netted (must preserve per-party, per-asset balances): same as originals here
    ICore.Flow[] memory netted = new ICore.Flow[](2);
    netted[0] = _createERC20Flow(alice, bob, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    netted[1] = _createERC20Flow(bob, charlie, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    dvp.executeSettlementNetted(settlementId, netted);

    vm.expectRevert(DeliveryVersusPaymentV1.SettlementAlreadyExecuted.selector);
    dvp.executeSettlementNetted(settlementId, netted);
  }

  function test_executeSettlementNetted_NetoffDisabled_Reverts() public {
    (ICore.Flow[] memory flows, uint256 cutoff, , , ) = _createMixedFlowsForNetting();
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);  // netoff disabled by default

    ICore.Flow[] memory netted = new ICore.Flow[](0);
    vm.expectRevert(DeliveryVersusPaymentV1.SettlementWithNettedFlowsNotAllowed.selector);
    dvp.executeSettlementNetted(settlementId, netted);

  }


  //--------------------------------------------------------------------------------
  // Validation failures inside executeSettlementNetted
  //--------------------------------------------------------------------------------
  function test_executeSettlementNetted_UnknownPartyInNettedFlow_Reverts() public {
    // Original simple
    ICore.Flow[] memory flows = new ICore.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, 100);
    uint256 settlementId = dvp.createSettlement(flows, _ref("unknown_party"), _getFutureTimestamp(3 days), false, true);

    _approveERC20(alice, usdc, 100);
    uint256[] memory ids = _getSettlementIdArray(settlementId);
    vm.prank(alice);
    dvp.approveSettlements(ids);
    ICore.Flow[] memory netted = new ICore.Flow[](1);
    // Dave is not part of original parties set
    netted[0] = _createERC20Flow(alice, dave, usdc, 100);

    vm.expectRevert(bytes("Unknown party in netted flow"));
    dvp.executeSettlementNetted(settlementId, netted);
  }

  function test_executeSettlementNetted_UnknownAssetInNettedFlow_Reverts() public {
    ICore.Flow[] memory flows = new ICore.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, 100);
    uint256 settlementId = dvp.createSettlement(flows, _ref("unknown_asset"), _getFutureTimestamp(3 days), false, true);

    _approveERC20(alice, usdc, 100);
    uint256[] memory ids = _getSettlementIdArray(settlementId);
    vm.prank(alice);
    dvp.approveSettlements(ids);
    ICore.Flow[] memory netted = new ICore.Flow[](1);
    // Use USDT which is not in original assets for this settlement
    netted[0] = _createERC20Flow(alice, bob, usdt, 100);

    vm.expectRevert(bytes("Unknown asset in netted flow"));
    dvp.executeSettlementNetted(settlementId, netted);
  }

  function test_executeSettlementNetted_ZeroNettedAmount_Reverts() public {
    ICore.Flow[] memory flows = new ICore.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, 100);
    uint256 settlementId = dvp.createSettlement(flows, _ref("zero_amt"), _getFutureTimestamp(3 days), false, true);

    _approveERC20(alice, usdc, 100);
    uint256[] memory ids = _getSettlementIdArray(settlementId);
    vm.prank(alice);
    dvp.approveSettlements(ids);
    ICore.Flow[] memory netted = new ICore.Flow[](1);
    netted[0] = _createERC20Flow(alice, bob, usdc, 0);

    vm.expectRevert(bytes("Zero netted amountOrId"));
    dvp.executeSettlementNetted(settlementId, netted);
  }

  function test_executeSettlementNetted_BalanceMismatch_Reverts() public {
    // Original: Alice->Bob 100 USDC
    ICore.Flow[] memory flows = new ICore.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, 100);
    uint256 settlementId = dvp.createSettlement(flows, _ref("bal_mismatch"), _getFutureTimestamp(3 days), false, true);

    _approveERC20(alice, usdc, 100);
    uint256[] memory ids = _getSettlementIdArray(settlementId);
    vm.prank(alice);
    dvp.approveSettlements(ids);
    // Provide netted that underpays (50 instead of 100)
    ICore.Flow[] memory netted = new ICore.Flow[](1);
    netted[0] = _createERC20Flow(alice, bob, usdc, 50);

    vm.expectRevert(bytes("Balance mismatch"));
    dvp.executeSettlementNetted(settlementId, netted);
  }

  function test_executeSettlementNetted_NFTAssetMustMatchTokenId() public {
    // Original: Alice -> Bob Daisy (id=1)
    ICore.Flow[] memory flows = new ICore.Flow[](1);
    flows[0] = _createNFTFlow(alice, bob, nftCat, NFT_CAT_DAISY);
    uint256 settlementId = dvp.createSettlement(flows, _ref("nft_key"), _getFutureTimestamp(3 days), false, true);

    _approveNFT(alice, nftCat, NFT_CAT_DAISY);
    uint256[] memory ids = _getSettlementIdArray(settlementId);
    vm.prank(alice);
    dvp.approveSettlements(ids);

    // Netted with same token contract but different tokenId must fail as unknown asset key
    ICore.Flow[] memory netted = new ICore.Flow[](1);
    netted[0] = _createNFTFlow(alice, bob, nftCat, NFT_CAT_BUTTONS);

    vm.expectRevert(bytes("Unknown asset in netted flow"));
    dvp.executeSettlementNetted(settlementId, netted);
  }

  //--------------------------------------------------------------------------------
  // Non-payable check: sending value should revert
  //--------------------------------------------------------------------------------
  function test_executeSettlementNetted_NonPayable_RevertsOnValue() public {
    ICore.Flow[] memory flows = _createERC20Flows();
    uint256 settlementId = dvp.createSettlement(flows, _ref("nonpayable"), _getFutureTimestamp(3 days), false, true);

    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    _approveERC20(bob, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    uint256[] memory ids = _getSettlementIdArray(settlementId);
    vm.prank(alice);
    dvp.approveSettlements(ids);

    ICore.Flow[] memory netted = new ICore.Flow[](2);
    netted[0] = _createERC20Flow(alice, charlie, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    netted[1] = _createERC20Flow(bob, alice, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    // Non-payable function: attempt low-level call with value should fail
    bytes memory data = abi.encodeWithSelector(DeliveryVersusPaymentV1.executeSettlementNetted.selector, settlementId, netted);
    (bool ok, ) = address(dvp).call{value: 1 wei}(data);
    assertFalse(ok, "Non-payable function accepted value");
  }

  //--------------------------------------------------------------------------------
  // Utility
  //--------------------------------------------------------------------------------
  function _ref(string memory tag) internal pure returns (string memory) {
    return string(abi.encodePacked(SETTLEMENT_REF, "-", tag));
  }
}
