// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./TestDvpBase.sol";
import "../src/dvp/V1/DeliveryVersusPaymentV1.sol";

/**
 * @title DeliveryVersusPaymentV1SettlementTest
 * @notice Tests settlement lifecycle operations including approvals for ERC20/ETH/NFT flows, settlement execution,
 * approval revocation, ETH withdrawal after expiry, auto-settlement execution, and error handling for invalid states.
 */
contract DeliveryVersusPaymentV1SettlementTest is TestDvpBase {
  //--------------------------------------------------------------------------------
  // approveSettlements Tests
  //--------------------------------------------------------------------------------
  function test_approveSettlements_WithERC20Flows_Succeeds() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Approve ERC20 transfers
    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    _approveERC20(bob, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    // Alice approves
    vm.expectEmit(true, true, false, true);
    emit DeliveryVersusPaymentV1.SettlementApproved(settlementId, alice);

    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    // Check settlement party status for Alice
    (bool isApproved, uint256 etherRequired, uint256 etherDeposited, ) = dvp.getSettlementPartyStatus(
      settlementId,
      alice
    );

    assertTrue(isApproved);
    assertEq(etherRequired, 0);
    assertEq(etherDeposited, 0);
  }

  function test_approveSettlements_WithETHFlows_Succeeds() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createETHFlows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    uint256 aliceETHRequired = TOKEN_AMOUNT_SMALL_18_DECIMALS;
    uint256 bobETHRequired = TOKEN_AMOUNT_SMALL_18_DECIMALS / 2;

    // Alice approves with ETH
    vm.expectEmit(true, true, false, true);
    emit DeliveryVersusPaymentV1.SettlementApproved(settlementId, alice);
    vm.expectEmit(true, false, false, true);
    emit DeliveryVersusPaymentV1.ETHReceived(alice, aliceETHRequired);

    vm.prank(alice);
    dvp.approveSettlements{value: aliceETHRequired}(settlementIds);

    // Check Alice's status
    (bool isApproved, uint256 etherRequired, uint256 etherDeposited, ) = dvp.getSettlementPartyStatus(
      settlementId,
      alice
    );

    assertTrue(isApproved);
    assertEq(etherRequired, aliceETHRequired);
    assertEq(etherDeposited, aliceETHRequired);

    // Bob approves with ETH
    vm.prank(bob);
    dvp.approveSettlements{value: bobETHRequired}(settlementIds);

    assertTrue(dvp.isSettlementApproved(settlementId));
  }

  function test_approveSettlements_WithNFTFlows_Succeeds() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createNFTFlows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Approve NFT transfers
    _approveNFT(alice, nftCat, NFT_CAT_DAISY);
    _approveNFT(charlie, nftDog, NFT_DOG_FIDO);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    // Alice approves
    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    // Charlie approves
    vm.prank(charlie);
    dvp.approveSettlements(settlementIds);

    assertTrue(dvp.isSettlementApproved(settlementId));
  }

  function test_approveSettlements_WithMixedFlows_Succeeds() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createMixedFlows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Approve transfers
    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    _approveERC20(charlie, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);
    _approveNFT(alice, nftCat, NFT_CAT_DAISY);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    uint256 bobETHRequired = TOKEN_AMOUNT_SMALL_18_DECIMALS;

    // All parties approve
    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    vm.prank(bob);
    dvp.approveSettlements{value: bobETHRequired}(settlementIds);

    vm.prank(charlie);
    dvp.approveSettlements(settlementIds);

    assertTrue(dvp.isSettlementApproved(settlementId));
  }

  function test_approveSettlements_WithExecutedSettlement_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, true); // auto-settle

    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    _approveERC20(bob, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    vm.prank(bob);
    dvp.approveSettlements(settlementIds); // This will auto-execute

    // Try to approve after execution
    vm.expectRevert(DeliveryVersusPaymentV1.SettlementAlreadyExecuted.selector);
    vm.prank(alice);
    dvp.approveSettlements(settlementIds);
  }

  function test_approveSettlements_WithInvalidId_Reverts() public {
    // Non-existent settlement id means revert
    vm.expectRevert(DeliveryVersusPaymentV1.SettlementDoesNotExist.selector);
    dvp.approveSettlements(_getInvalidSettlementIdArray());
  }

  function test_approveSettlements_WithIncorrectETHAmount_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createETHFlows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    uint256 correctAmount = TOKEN_AMOUNT_SMALL_18_DECIMALS;
    uint256 incorrectAmount = correctAmount / 2;

    vm.expectRevert(abi.encodeWithSelector(DeliveryVersusPaymentV1.IncorrectETHAmount.selector, incorrectAmount, correctAmount));
    vm.prank(alice);
    dvp.approveSettlements{value: incorrectAmount}(settlementIds);
  }

  function test_approveSettlements_WithAlreadyGrantedApproval_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    // First approval succeeds
    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    // Second approval reverts
    vm.expectRevert(DeliveryVersusPaymentV1.ApprovalAlreadyGranted.selector);
    vm.prank(alice);
    dvp.approveSettlements(settlementIds);
  }

  function test_approveSettlements_WithNonInvolvedParty_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.expectRevert(DeliveryVersusPaymentV1.CallerNotInvolved.selector);
    vm.prank(dave); // Dave is not involved in the flows
    dvp.approveSettlements(settlementIds);
  }

  function test_approveSettlements_WithExpiredSettlement_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(1);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Move past cutoff
    _advanceTime(2 days);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.expectRevert(DeliveryVersusPaymentV1.CutoffDatePassed.selector);
    vm.prank(alice);
    dvp.approveSettlements(settlementIds);
  }

  function test_approveSettlements_WithAutoSettlement_ExecutesAutomatically() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, true);

    // Approve ERC20 transfers
    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    _approveERC20(bob, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    // Alice approves first - not auto-executed yet
    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    // Check settlement is not executed yet
    (, , , , , bool isSettled, , ) = dvp.getSettlement(settlementId);
    assertFalse(isSettled);

    // Bob approves last - triggers auto-execution
    vm.expectEmit(true, true, false, true);
    emit DeliveryVersusPaymentV1.SettlementExecuted(settlementId, bob);
    vm.prank(bob);
    dvp.approveSettlements(settlementIds);

    // Check settlement is executed
    (, , , , , isSettled, , ) = dvp.getSettlement(settlementId);
    assertTrue(isSettled);
  }

  function test_autoExecuteSettlement_WithERC20TransferFailureReasonString_Succeeds() public {
    // Auto-executing settlements can fail to execute, but should retain the approval that triggered it
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(dave, alice, address(assetTokenThatReverts), AMOUNT_FOR_REVERT_REASON_STRING);
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, true);

    // Approve
    _approveERC20(dave, address(assetTokenThatReverts), AMOUNT_FOR_REVERT_REASON_STRING);

    // Auto execution fails because transfer of AMOUNT_FOR_REVERT_REASON_STRING causes that transfer to revert
    // with a reason string. However, overall transaction should succeed and approval should stick
    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);
    vm.prank(dave);
    dvp.approveSettlements(settlementIds);

    (bool isApproved, , , ) = dvp.getSettlementPartyStatus(settlementId, dave);
    assertTrue(isApproved, "Approval should still be retained after auto-execution failure");
  }

  function test_autoExecuteSettlement_WithERC20TransferFailurePanic_Succeeds() public {
    // Auto-executing settlements can fail to execute, but should retain the approval that triggered it
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(dave, alice, address(assetTokenThatReverts), AMOUNT_FOR_REVERT_PANIC);
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, true);

    // Approve
    _approveERC20(dave, address(assetTokenThatReverts), AMOUNT_FOR_REVERT_PANIC);

    // Auto execution fails because transfer of AMOUNT_FOR_REVERT_PANIC causes that transfer to revert
    // with panic. However, overall transaction should succeed and approval should stick
    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);
    vm.prank(dave);
    dvp.approveSettlements(settlementIds);

    (bool isApproved, , , ) = dvp.getSettlementPartyStatus(settlementId, dave);
    assertTrue(isApproved, "Approval should still be retained after auto-execution failure");
  }

  //--------------------------------------------------------------------------------
  // executeSettlement Tests
  //--------------------------------------------------------------------------------
  function test_executeSettlement_WithValidERC20Settlement_Succeeds() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Get initial balances
    uint256 aliceUSDCBefore = usdcToken.balanceOf(alice);
    uint256 bobUSDCBefore = usdcToken.balanceOf(bob);
    uint256 bobDAIBefore = daiToken.balanceOf(bob);
    uint256 charlieDAIBefore = daiToken.balanceOf(charlie);

    // Approve and execute
    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    _approveERC20(bob, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    vm.prank(bob);
    dvp.approveSettlements(settlementIds);

    vm.expectEmit(true, true, false, true);
    emit DeliveryVersusPaymentV1.SettlementExecuted(settlementId, address(this));
    dvp.executeSettlement(settlementId);

    // Check balances after execution
    assertEq(usdcToken.balanceOf(alice), aliceUSDCBefore - TOKEN_AMOUNT_SMALL_6_DECIMALS);
    assertEq(usdcToken.balanceOf(bob), bobUSDCBefore + TOKEN_AMOUNT_SMALL_6_DECIMALS);
    assertEq(daiToken.balanceOf(bob), bobDAIBefore - TOKEN_AMOUNT_SMALL_18_DECIMALS);
    assertEq(daiToken.balanceOf(charlie), charlieDAIBefore + TOKEN_AMOUNT_SMALL_18_DECIMALS);

    // Check settlement is marked as settled
    (, , , , , bool isSettled, , ) = dvp.getSettlement(settlementId);
    assertTrue(isSettled);
  }

  function test_executeSettlement_WithValidETHSettlement_Succeeds() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createETHFlows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Get initial balances
    uint256 bobETHBefore = bob.balance;
    uint256 charlieETHBefore = charlie.balance;

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    uint256 aliceETHRequired = TOKEN_AMOUNT_SMALL_18_DECIMALS;
    uint256 bobETHRequired = TOKEN_AMOUNT_SMALL_18_DECIMALS / 2;

    // Approve with ETH deposits
    vm.prank(alice);
    dvp.approveSettlements{value: aliceETHRequired}(settlementIds);

    vm.prank(bob);
    dvp.approveSettlements{value: bobETHRequired}(settlementIds);

    // Execute settlement
    dvp.executeSettlement(settlementId);

    // Check ETH balances (accounting for gas costs is complex, so we check relative changes)
    assertEq(bob.balance, bobETHBefore - bobETHRequired + aliceETHRequired);
    assertEq(charlie.balance, charlieETHBefore + bobETHRequired);
  }

  function test_executeSettlement_WithValidNFTSettlement_Succeeds() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createNFTFlows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Check initial owners
    assertEq(nftCatToken.ownerOf(NFT_CAT_DAISY), alice);
    assertEq(nftDogToken.ownerOf(NFT_DOG_FIDO), charlie);

    // Approve and execute
    _approveNFT(alice, nftCat, NFT_CAT_DAISY);
    _approveNFT(charlie, nftDog, NFT_DOG_FIDO);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    vm.prank(charlie);
    dvp.approveSettlements(settlementIds);

    dvp.executeSettlement(settlementId);

    // Check owners after execution
    assertEq(nftCatToken.ownerOf(NFT_CAT_DAISY), bob);
    assertEq(nftDogToken.ownerOf(NFT_DOG_FIDO), alice);
  }

  function test_executeSettlement_MixedWithNettingOff_SucceedsAndRefundsETH() public {
    // Arrange
    (IDeliveryVersusPaymentV1.Flow[] memory flows, IDeliveryVersusPaymentV1.Flow[] memory nettedFlows, uint256 cutoff, uint256 ethA, uint256 ethB, uint256 ethC) = _createMixedFlowsForNetting();

    uint256 settlementId = dvp.createSettlement(flows, nettedFlows, SETTLEMENT_REF, cutoff, false);

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

    // Snapshot balances for assertions
    uint256 aliceUSDCBefore = AssetToken(usdc).balanceOf(alice);
    uint256 bobUSDCBefore = AssetToken(usdc).balanceOf(bob);
    uint256 charlieUSDCBefore = AssetToken(usdc).balanceOf(charlie);
    address prevOwnerDaisy = NFT(nftCat).ownerOf(NFT_CAT_DAISY);

    // Act
    vm.expectEmit(true, true, true, true, address(usdc));
    emit IERC20.Transfer(alice, bob, 20);
    emit IERC20.Transfer(alice, charlie, 30);
    vm.expectEmit(true, true, true, true, nftCat);
    emit IERC721.Transfer(alice, charlie, NFT_CAT_DAISY);

    dvp.executeSettlement(settlementId);

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
    (, , , , , bool isSettled, , ) = dvp.getSettlement(settlementId);
    assertTrue(isSettled);
  }

  function test_executeSettlement_WithNotApproved_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    vm.expectRevert(DeliveryVersusPaymentV1.SettlementNotApproved.selector);
    dvp.executeSettlement(settlementId);
  }

  function test_executeSettlement_WithExpiredSettlement_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(1);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    _advanceTime(2 days);

    vm.expectRevert(DeliveryVersusPaymentV1.CutoffDatePassed.selector);
    dvp.executeSettlement(settlementId);
  }

  function test_executeSettlement_WithAlreadyExecuted_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    _approveERC20(bob, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    vm.prank(bob);
    dvp.approveSettlements(settlementIds);

    // First execution succeeds
    dvp.executeSettlement(settlementId);

    // Second execution reverts
    vm.expectRevert(DeliveryVersusPaymentV1.SettlementAlreadyExecuted.selector);
    dvp.executeSettlement(settlementId);
  }

  function test_executeSettlement_WithInvalidId_Reverts() public {
    // Non-existent settlement id means revert
    vm.expectRevert(DeliveryVersusPaymentV1.SettlementDoesNotExist.selector);
    dvp.executeSettlement(NOT_A_SETTLEMENT_ID);
  }

  function test_executeSettlementInternal_WithExternalCaller_Reverts() public {
    // executeSettlementInner() should behave like an internal function, and revert if caller is not the self contract
    vm.expectRevert(DeliveryVersusPaymentV1.CallerMustBeDvpContract.selector);
    dvp.executeSettlementInner(address(this), NOT_A_SETTLEMENT_ID);
  }

  //--------------------------------------------------------------------------------
  // revokeApprovals Tests
  //--------------------------------------------------------------------------------
  function test_revokeApprovals_WithValidApproval_Succeeds() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createETHFlows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    uint256 aliceETHRequired = TOKEN_AMOUNT_SMALL_18_DECIMALS;
    uint256 aliceETHBefore = alice.balance;

    // Alice approves with ETH
    vm.prank(alice);
    dvp.approveSettlements{value: aliceETHRequired}(settlementIds);

    // Verify approval and deposit
    (bool isApproved, , uint256 etherDeposited, ) = dvp.getSettlementPartyStatus(settlementId, alice);
    assertTrue(isApproved);
    assertEq(etherDeposited, aliceETHRequired);

    // Alice revokes approval
    vm.expectEmit(true, false, false, true);
    emit DeliveryVersusPaymentV1.ETHWithdrawn(alice, aliceETHRequired);
    vm.expectEmit(true, true, false, true);
    emit DeliveryVersusPaymentV1.SettlementApprovalRevoked(settlementId, alice);
    vm.prank(alice);
    dvp.revokeApprovals(settlementIds);

    // Check approval is revoked and ETH refunded
    (isApproved, , etherDeposited, ) = dvp.getSettlementPartyStatus(settlementId, alice);
    assertFalse(isApproved);
    assertEq(etherDeposited, 0);
    assertEq(alice.balance, aliceETHBefore); // Should get ETH back (minus gas)
  }

  function test_revokeApprovals_WithInvalidId_Reverts() public {
    // Non-existent settlement id means revert
    vm.expectRevert(DeliveryVersusPaymentV1.SettlementDoesNotExist.selector);
    dvp.revokeApprovals(_getInvalidSettlementIdArray());
  }

  function test_revokeApprovals_WithoutApproval_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.expectRevert(DeliveryVersusPaymentV1.ApprovalNotGranted.selector);
    vm.prank(alice);
    dvp.revokeApprovals(settlementIds);
  }

  function test_revokeApprovals_WithExecutedSettlement_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, true); // auto-settle

    _approveERC20(alice, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    _approveERC20(bob, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.prank(alice);
    dvp.approveSettlements(settlementIds);

    vm.prank(bob);
    dvp.approveSettlements(settlementIds); // This will auto-execute

    // Try to revoke after execution
    vm.expectRevert(DeliveryVersusPaymentV1.SettlementAlreadyExecuted.selector);
    vm.prank(alice);
    dvp.revokeApprovals(settlementIds);
  }

  //--------------------------------------------------------------------------------
  // withdrawETH Tests
  //--------------------------------------------------------------------------------
  function test_withdrawETH_AfterExpiry_Succeeds() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createETHFlows();
    uint256 cutoff = _getFutureTimestamp(1);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    uint256 aliceETHRequired = TOKEN_AMOUNT_SMALL_18_DECIMALS;

    // Alice approves with ETH but Bob doesn't approve
    vm.prank(alice);
    dvp.approveSettlements{value: aliceETHRequired}(settlementIds);

    // Move past cutoff
    _advanceTime(2 days);

    // Alice can withdraw her ETH
    vm.expectEmit(true, false, false, true);
    emit DeliveryVersusPaymentV1.ETHWithdrawn(alice, aliceETHRequired);

    vm.prank(alice);
    dvp.withdrawETH(settlementId);

    // Check ETH is returned
    (, , uint256 etherDeposited, ) = dvp.getSettlementPartyStatus(settlementId, alice);
    assertEq(etherDeposited, 0);
  }

  function test_withdrawETH_BeforeExpiry_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createETHFlows();
    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.prank(alice);
    dvp.approveSettlements{value: TOKEN_AMOUNT_SMALL_18_DECIMALS}(settlementIds);

    vm.expectRevert(DeliveryVersusPaymentV1.CutoffDateNotPassed.selector);
    vm.prank(alice);
    dvp.withdrawETH(settlementId);
  }

  function test_withdrawETH_WithInvalidId_Reverts() public {
    // Non-existent settlement id means revert
    vm.expectRevert(DeliveryVersusPaymentV1.SettlementDoesNotExist.selector);
    dvp.withdrawETH(NOT_A_SETTLEMENT_ID);
  }

  function test_withdrawETH_WithNoDeposit_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createERC20Flows();
    uint256 cutoff = _getFutureTimestamp(1);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, false);

    // Move past cutoff
    _advanceTime(1 days);

    vm.expectRevert(DeliveryVersusPaymentV1.NoETHToWithdraw.selector);
    vm.prank(alice);
    dvp.withdrawETH(settlementId);
  }

  function test_withdrawETH_WithExecutedSettlement_Reverts() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = _createETHFlows();
    uint256 cutoff = _getFutureTimestamp(1);
    uint256 settlementId = dvp.createSettlement(flows, SETTLEMENT_REF, cutoff, true);

    uint256[] memory settlementIds = _getSettlementIdArray(settlementId);

    vm.prank(alice);
    dvp.approveSettlements{value: TOKEN_AMOUNT_SMALL_18_DECIMALS}(settlementIds);

    vm.prank(bob);
    dvp.approveSettlements{value: TOKEN_AMOUNT_SMALL_18_DECIMALS / 2}(settlementIds); // auto executes

    // Move past cutoff
    _advanceTime(1 days);

    vm.expectRevert(DeliveryVersusPaymentV1.SettlementAlreadyExecuted.selector);
    vm.prank(alice);
    dvp.withdrawETH(settlementId);
  }

  function test_setNettedFlows_Success() public {
    IDeliveryVersusPaymentV1.Flow[] memory nettedFlows;
    bool useNettingOff;

    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, 20);

    uint256 settlementId = dvp.createSettlement(flows, _ref('set_netted_flows'), _getFutureTimestamp(1), false);

    ( , , , nettedFlows, , , , useNettingOff) = dvp.getSettlement(settlementId);

    assertEq(nettedFlows.length, 0);
    assertFalse(useNettingOff);

    nettedFlows = new IDeliveryVersusPaymentV1.Flow[](1);
    nettedFlows[0] = _createERC20Flow(alice, bob, usdc, 20);

    // Act
    dvp.setNettedFlows(settlementId, nettedFlows);

    ( , , , nettedFlows, , , , useNettingOff) = dvp.getSettlement(settlementId);

    // Assert
    assertEq(nettedFlows.length, 1);
    assertTrue(useNettingOff);
  }

  function test_setNettedFlows_CalledMultipleTimesSuccess() public {
    IDeliveryVersusPaymentV1.Flow[] memory nettedFlows;
    bool useNettingOff;

    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](3);
    flows[0] = _createERC20Flow(alice, bob, usdc, 10);
    flows[1] = _createERC20Flow(alice, bob, usdc, 20);
    flows[2] = _createERC20Flow(alice, bob, usdc, 40);

    uint256 settlementId = dvp.createSettlement(flows, _ref('set_netted_flows'), _getFutureTimestamp(1), false);

    IDeliveryVersusPaymentV1.Flow[] memory nettedFlows1 = new IDeliveryVersusPaymentV1.Flow[](2);
    nettedFlows1[0] = _createERC20Flow(alice, bob, usdc, 50);
    nettedFlows1[1] = _createERC20Flow(alice, bob, usdc, 20);

    dvp.setNettedFlows(settlementId, nettedFlows1);

    ( , , , nettedFlows, , , , useNettingOff) = dvp.getSettlement(settlementId);

    assertEq(nettedFlows.length, 2);
    assertTrue(useNettingOff);

    IDeliveryVersusPaymentV1.Flow[] memory nettedFlows2 = new IDeliveryVersusPaymentV1.Flow[](1);
    nettedFlows2[0] = _createERC20Flow(alice, bob, usdc, 70);

    dvp.setNettedFlows(settlementId, nettedFlows2);

    ( , , , nettedFlows, , , , useNettingOff) = dvp.getSettlement(settlementId);

    assertEq(nettedFlows.length, 1);
    assertTrue(useNettingOff);
  }

  function test_setNettedFlows_RevertsIfSettlementDoesNotExist() public {
      // Arrange
      IDeliveryVersusPaymentV1.Flow[] memory nettedFlows = new IDeliveryVersusPaymentV1.Flow[](1);
      nettedFlows[0] = _createERC20Flow(alice, bob, usdc, 20);

      // Act & Assert
      vm.expectRevert(DeliveryVersusPaymentV1.SettlementDoesNotExist.selector);
      dvp.setNettedFlows(1, nettedFlows);  // No settlement with ID 1
  }

  function test_setNettedFlows_RevertsIfSettlementAlreadyExecuted() public {
    // Arrange
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, 20);

    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, _ref("already_executed"), cutoff, false);

    _approveERC20(alice, usdc, 20);
    vm.prank(alice);
    dvp.approveSettlements(_getSettlementIdArray(settlementId));
    dvp.executeSettlement(settlementId);

    // Act & Assert
    vm.expectRevert(DeliveryVersusPaymentV1.SettlementAlreadyExecuted.selector);
    dvp.setNettedFlows(settlementId, flows);  // using original flows as dummy netted flows
  }

  function test_setNettedFlows_RevertsIfCutoffDatePassed() public {
    // Arrange
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, 20);

    uint256 cutoff = _getFutureTimestamp(1 days);
    uint256 settlementId = dvp.createSettlement(flows, _ref("cutoff_passed"), cutoff, false);

    // Act & Assert
    _advanceTime(2 days);
    vm.expectRevert(DeliveryVersusPaymentV1.CutoffDatePassed.selector);
    dvp.setNettedFlows(settlementId, flows);  // using original flows as dummy netted flows
  }
//
  function test_setNettedFlows_revertsIfCallerIsNotCreator() public {
    // Arrange
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, 20);

    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, _ref("caller_not_creator"), cutoff, false);

    // Act & Assert
    vm.prank(bob); // Bob is not the creator
    vm.expectRevert(DeliveryVersusPaymentV1.CallerMustBeSettlementCreator.selector);
    dvp.setNettedFlows(settlementId, flows);  // using original flows as dummy netted flows
  }

  function test_setNettedFlows_RevertsIfNettedFlowsNotEquivalent() public {
    // Arrange
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, 20);

    IDeliveryVersusPaymentV1.Flow[] memory nettedFlows = new IDeliveryVersusPaymentV1.Flow[](0);

    uint256 cutoff = _getFutureTimestamp(7 days);
    uint256 settlementId = dvp.createSettlement(flows, _ref("caller_not_creator"), cutoff, false);

    // Act & Assert
    vm.expectRevert(DeliveryVersusPaymentV1.NotEquivalentNettedFlows.selector);
    dvp.setNettedFlows(settlementId, nettedFlows);
  }

}
