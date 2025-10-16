// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./TestDvpBase.sol";

/**
 * @title DeliveryVersusPaymentV1HelperV1Test
 * @notice Tests helper contract functionality including settlement querying by token, involved party, and token type,
 * pagination behavior, token type enumeration, and comprehensive search capabilities across multiple settlement types.
 */
contract DeliveryVersusPaymentV1HelperV1Test is TestDvpBase {
  uint256[] public settlementIds;

  enum TokenType {
    Ether, // Settlements containing any flow with Ether (token == address(0))
    ERC20, // Settlements containing any flow with an ERC20 token (token != address(0) && isNFT == false)
    NFT // Settlements containing any flow with an NFT (token != address(0) && isNFT == true)
  }

  function setUp() public override {
    super.setUp();
    _createTestSettlements();
  }

  function _createTestSettlements() internal {
    uint256 cutoff = _getFutureTimestamp(7 days);

    // Create 10 settlements for each type: mixed, NFT-only, ERC20-only, Ether-only
    for (uint256 i = 0; i < 10; i++) {
      // Mixed flows (contain multiple token types)
      IDeliveryVersusPaymentV1.Flow[] memory mixedFlows = _createMixedFlows();
      uint256 mixedId = dvp.createSettlement(mixedFlows, string(abi.encodePacked("Type mixed ", i)), cutoff, false);
      settlementIds.push(mixedId);

      // NFT-only flows
      IDeliveryVersusPaymentV1.Flow[] memory nftFlows = _createNFTFlows();
      uint256 nftId = dvp.createSettlement(nftFlows, string(abi.encodePacked("Type NFT ", i)), cutoff, false);
      settlementIds.push(nftId);

      // ERC20-only flows
      IDeliveryVersusPaymentV1.Flow[] memory erc20Flows = _createERC20Flows();
      uint256 erc20Id = dvp.createSettlement(erc20Flows, string(abi.encodePacked("Type ERC20 ", i)), cutoff, false);
      settlementIds.push(erc20Id);

      // Ether-only flows
      IDeliveryVersusPaymentV1.Flow[] memory ethFlows = _createETHFlows();
      uint256 ethId = dvp.createSettlement(ethFlows, string(abi.encodePacked("Type Ether ", i)), cutoff, false);
      settlementIds.push(ethId);
    }
  }

  /**
   * @dev Compares two `NetRequirement` structs for equality.
   * This function checks if the `ethRequiredNet` values are equal,
   * and then verifies that the lengths of the `erc20Tokens` and `erc20NetRequired` arrays match.
   * Finally, it iterates through the arrays to ensure all corresponding elements are equal.
   *
   * @param a The first `NetRequirement` struct to compare.
   * @param b The second `NetRequirement` struct to compare.
   */
  function _assertEqNetRequirement(
    DeliveryVersusPaymentV1HelperV1.NetRequirement memory a,
    DeliveryVersusPaymentV1HelperV1.NetRequirement memory b
  ) internal {
    // Assert that the net ETH requirements are equal
    assertEq(a.ethRequiredNet, b.ethRequiredNet);

    // Assert that the lengths of the ERC20 tokens arrays are equal
    assertEq(a.erc20Tokens.length, b.erc20Tokens.length);

    // Assert that the lengths of the ERC20 net required arrays are equal
    assertEq(a.erc20NetRequired.length, b.erc20NetRequired.length);

    // Iterate through the ERC20 tokens and net required arrays to compare each element
    for (uint256 i = 0; i < a.erc20Tokens.length; i++) {
      assertEq(a.erc20Tokens[i], b.erc20Tokens[i]);
      assertEq(a.erc20NetRequired[i], b.erc20NetRequired[i]);
    }
  }

  //--------------------------------------------------------------------------------
  // getTokenTypes Tests
  //--------------------------------------------------------------------------------
  function test_getTokenTypes_ReturnsCorrectTypes() public view {
    DeliveryVersusPaymentV1HelperV1.TokenTypeInfo[] memory types = dvpHelper.getTokenTypes();

    assertEq(types.length, 3);

    assertEq(types[0].id, uint8(TokenType.Ether));
    assertEq(types[0].name, "Ether");

    assertEq(types[1].id, uint8(TokenType.ERC20));
    assertEq(types[1].name, "ERC20");

    assertEq(types[2].id, uint8(TokenType.NFT));
    assertEq(types[2].name, "NFT");
  }

  //--------------------------------------------------------------------------------
  // getSettlementsByToken Tests
  //--------------------------------------------------------------------------------
  function test_getSettlementsByToken_WithUSDC_ReturnsMatchingSettlements() public view {
    uint256 pageSize = 5;
    (uint256[] memory returnedIds,) = dvpHelper.getSettlementsByToken(address(dvp), usdc, 0, pageSize);

    assertGt(returnedIds.length, 0);
    assertLe(returnedIds.length, pageSize);

    // Verify that each settlement includes at least one flow with token == usdc
    for (uint256 i = 0; i < returnedIds.length; i++) {
      (,, IDeliveryVersusPaymentV1.Flow[] memory flows,,,,,) = dvp.getSettlement(returnedIds[i]);
      bool hasUSDC = false;
      for (uint256 j = 0; j < flows.length; j++) {
        if (flows[j].token == usdc) {
          hasUSDC = true;
          break;
        }
      }
      assertTrue(hasUSDC, "Settlement should contain USDC flow");
    }
  }

  function test_getSettlementsByToken_WithNonExistentToken_ReturnsEmpty() public view {
    address randomToken = address(0x1234567890123456789012345678901234567890);
    uint256 pageSize = 5;

    (uint256[] memory returnedIds, uint256 nextCursor) =
      dvpHelper.getSettlementsByToken(address(dvp), randomToken, 0, pageSize);

    assertEq(returnedIds.length, 0);
    assertEq(nextCursor, 0);
  }

  function test_getSettlementsByToken_WithInvalidPageSize_Reverts() public {
    vm.expectRevert(DeliveryVersusPaymentV1HelperV1.InvalidPageSize.selector);
    dvpHelper.getSettlementsByToken(address(dvp), usdc, 0, 1);

    vm.expectRevert(DeliveryVersusPaymentV1HelperV1.InvalidPageSize.selector);
    dvpHelper.getSettlementsByToken(address(dvp), usdc, 0, 201);
  }

  function test_getSettlementsByToken_WithPagination_WorksCorrectly() public view {
    uint256 pageSize = 3;
    uint256[] memory allIds = new uint256[](40);
    uint256 totalCount = 0;
    uint256 cursor = 0;

    do {
      (uint256[] memory returnedIds, uint256 nextCursor) =
        dvpHelper.getSettlementsByToken(address(dvp), usdc, cursor, pageSize);

      for (uint256 i = 0; i < returnedIds.length; i++) {
        allIds[totalCount] = returnedIds[i];
        totalCount++;
      }
      cursor = nextCursor;
    } while (cursor != 0);

    assertGt(totalCount, 0);

    // Verify no duplicates
    for (uint256 i = 0; i < totalCount; i++) {
      for (uint256 j = i + 1; j < totalCount; j++) {
        assertNotEq(allIds[i], allIds[j], "Found duplicate settlement ID");
      }
    }
  }

  //--------------------------------------------------------------------------------
  // getSettlementsByInvolvedParty Tests
  //--------------------------------------------------------------------------------
  function test_getSettlementsByInvolvedParty_WithBob_ReturnsMatchingSettlements() public view {
    uint256 pageSize = 5;
    (uint256[] memory returnedIds,) = dvpHelper.getSettlementsByInvolvedParty(address(dvp), bob, 0, pageSize);

    assertGt(returnedIds.length, 0);

    // Verify that each settlement involves Bob
    for (uint256 i = 0; i < returnedIds.length; i++) {
      (,, IDeliveryVersusPaymentV1.Flow[] memory flows,,,,,) = dvp.getSettlement(returnedIds[i]);
      bool involvesBob = false;
      for (uint256 j = 0; j < flows.length; j++) {
        if (flows[j].from == bob || flows[j].to == bob) {
          involvesBob = true;
          break;
        }
      }
      assertTrue(involvesBob, "Settlement should involve Bob");
    }
  }

  function test_getSettlementsByInvolvedParty_WithNonInvolvedParty_ReturnsEmpty() public view {
    address randomParty = address(0x1234567890123456789012345678901234567890);
    uint256 pageSize = 5;

    (uint256[] memory returnedIds,) = dvpHelper.getSettlementsByInvolvedParty(address(dvp), randomParty, 0, pageSize);

    assertEq(returnedIds.length, 0);
  }

  function test_getSettlementsByInvolvedParty_WithInvalidPageSize_Reverts() public {
    vm.expectRevert(DeliveryVersusPaymentV1HelperV1.InvalidPageSize.selector);
    dvpHelper.getSettlementsByInvolvedParty(address(dvp), bob, 0, 1);

    vm.expectRevert(DeliveryVersusPaymentV1HelperV1.InvalidPageSize.selector);
    dvpHelper.getSettlementsByInvolvedParty(address(dvp), bob, 0, 201);
  }

  //--------------------------------------------------------------------------------
  // getSettlementsByTokenType Tests
  //--------------------------------------------------------------------------------
  function test_getSettlementsByTokenType_WithEther_ReturnsMatchingSettlements() public view {
    uint256 pageSize = 5;
    (uint256[] memory returnedIds,) =
      dvpHelper.getSettlementsByTokenType(address(dvp), DeliveryVersusPaymentV1HelperV1.TokenType.Ether, 0, pageSize);

    assertGt(returnedIds.length, 0);

    // Verify that each settlement has at least one Ether flow
    for (uint256 i = 0; i < returnedIds.length; i++) {
      (,, IDeliveryVersusPaymentV1.Flow[] memory flows,,,,,) = dvp.getSettlement(returnedIds[i]);
      bool hasEtherFlow = false;
      for (uint256 j = 0; j < flows.length; j++) {
        if (flows[j].token == address(0)) {
          hasEtherFlow = true;
          break;
        }
      }
      assertTrue(hasEtherFlow, "Settlement should contain Ether flow");
    }
  }

  function test_getSettlementsByTokenType_WithERC20_ReturnsMatchingSettlements() public view {
    uint256 pageSize = 5;
    (uint256[] memory returnedIds,) =
      dvpHelper.getSettlementsByTokenType(address(dvp), DeliveryVersusPaymentV1HelperV1.TokenType.ERC20, 0, pageSize);

    assertGt(returnedIds.length, 0);

    // Verify that each settlement has at least one ERC20 flow
    for (uint256 i = 0; i < returnedIds.length; i++) {
      (,, IDeliveryVersusPaymentV1.Flow[] memory flows,,,,,) = dvp.getSettlement(returnedIds[i]);
      bool hasERC20Flow = false;
      for (uint256 j = 0; j < flows.length; j++) {
        if (flows[j].token != address(0) && !flows[j].isNFT) {
          hasERC20Flow = true;
          break;
        }
      }
      assertTrue(hasERC20Flow, "Settlement should contain ERC20 flow");
    }
  }

  function test_getSettlementsByTokenType_WithNFT_ReturnsMatchingSettlements() public view {
    uint256 pageSize = 5;
    (uint256[] memory returnedIds,) =
      dvpHelper.getSettlementsByTokenType(address(dvp), DeliveryVersusPaymentV1HelperV1.TokenType.NFT, 0, pageSize);

    assertGt(returnedIds.length, 0);

    // Verify that each settlement has at least one NFT flow
    for (uint256 i = 0; i < returnedIds.length; i++) {
      (,, IDeliveryVersusPaymentV1.Flow[] memory flows,,,,,) = dvp.getSettlement(returnedIds[i]);
      bool hasNFTFlow = false;
      for (uint256 j = 0; j < flows.length; j++) {
        if (flows[j].token != address(0) && flows[j].isNFT) {
          hasNFTFlow = true;
          break;
        }
      }
      assertTrue(hasNFTFlow, "Settlement should contain NFT flow");
    }
  }

  function test_getSettlementsByTokenType_WithInvalidPageSize_Reverts() public {
    vm.expectRevert(DeliveryVersusPaymentV1HelperV1.InvalidPageSize.selector);
    dvpHelper.getSettlementsByTokenType(address(dvp), DeliveryVersusPaymentV1HelperV1.TokenType.Ether, 0, 1);

    vm.expectRevert(DeliveryVersusPaymentV1HelperV1.InvalidPageSize.selector);
    dvpHelper.getSettlementsByTokenType(address(dvp), DeliveryVersusPaymentV1HelperV1.TokenType.Ether, 0, 201);
  }

  function test_getSettlementsByTokenType_WithNonZeroStartCursor_WorksCorrectly() public view {
    uint256 pageSize = 5;

    // First call with startCursor = 0 to get the nextCursor
    (uint256[] memory firstPageIds, uint256 nextCursor) =
      dvpHelper.getSettlementsByTokenType(address(dvp), DeliveryVersusPaymentV1HelperV1.TokenType.ERC20, 0, pageSize);

    assertGt(firstPageIds.length, 0);

    // Only proceed if there is a valid nextCursor (non-zero)
    if (nextCursor != 0) {
      (uint256[] memory nextPageIds,) = dvpHelper.getSettlementsByTokenType(
        address(dvp), DeliveryVersusPaymentV1HelperV1.TokenType.ERC20, nextCursor, pageSize
      );

      // Verify that the call with a nonzero startCursor returns an array (could be empty or not)
      // and that if there are results, they're different from the first page
      if (nextPageIds.length > 0) {
        bool foundDuplicate = false;
        for (uint256 i = 0; i < firstPageIds.length; i++) {
          for (uint256 j = 0; j < nextPageIds.length; j++) {
            if (firstPageIds[i] == nextPageIds[j]) {
              foundDuplicate = true;
              break;
            }
          }
          if (foundDuplicate) break;
        }
        assertFalse(foundDuplicate, "Pages should not contain duplicate settlement IDs");
      }
    }
  }

  //--------------------------------------------------------------------------------
  // Pagination Tests
  //--------------------------------------------------------------------------------
  function test_paginationBehavior_ForGetSettlementsByToken() public view {
    uint256 pageSize = 3;
    uint256[] memory allIds = new uint256[](40);
    uint256 totalCount = 0;
    uint256 cursor = 0;

    do {
      (uint256[] memory returnedIds, uint256 nextCursor) =
        dvpHelper.getSettlementsByToken(address(dvp), usdc, cursor, pageSize);

      for (uint256 i = 0; i < returnedIds.length; i++) {
        allIds[totalCount] = returnedIds[i];
        totalCount++;
      }
      cursor = nextCursor;
    } while (cursor != 0);

    assertGt(totalCount, 0);

    // Ensure there are no duplicate IDs
    for (uint256 i = 0; i < totalCount; i++) {
      for (uint256 j = i + 1; j < totalCount; j++) {
        if (allIds[i] != 0 && allIds[j] != 0) {
          assertNotEq(allIds[i], allIds[j], "Found duplicate settlement ID in pagination");
        }
      }
    }
  }

  function test_paginationBehavior_ForGetSettlementsByInvolvedParty() public view {
    uint256 pageSize = 4;
    uint256[] memory allIds = new uint256[](40);
    uint256 totalCount = 0;
    uint256 cursor = 0;

    do {
      (uint256[] memory returnedIds, uint256 nextCursor) =
        dvpHelper.getSettlementsByInvolvedParty(address(dvp), alice, cursor, pageSize);

      for (uint256 i = 0; i < returnedIds.length; i++) {
        allIds[totalCount] = returnedIds[i];
        totalCount++;
      }
      cursor = nextCursor;
    } while (cursor != 0);

    assertGt(totalCount, 0);

    // Ensure there are no duplicate IDs
    for (uint256 i = 0; i < totalCount; i++) {
      for (uint256 j = i + 1; j < totalCount; j++) {
        if (allIds[i] != 0 && allIds[j] != 0) {
          assertNotEq(allIds[i], allIds[j], "Found duplicate settlement ID in pagination");
        }
      }
    }
  }

  function test_paginationBehavior_ForGetSettlementsByTokenType() public view {
    uint256 pageSize = 6;
    uint256[] memory allIds = new uint256[](40);
    uint256 totalCount = 0;
    uint256 cursor = 0;

    do {
      (uint256[] memory returnedIds, uint256 nextCursor) = dvpHelper.getSettlementsByTokenType(
        address(dvp), DeliveryVersusPaymentV1HelperV1.TokenType.ERC20, cursor, pageSize
      );

      for (uint256 i = 0; i < returnedIds.length; i++) {
        allIds[totalCount] = returnedIds[i];
        totalCount++;
      }
      cursor = nextCursor;
    } while (cursor != 0);

    assertGt(totalCount, 0);

    // Ensure there are no duplicate IDs
    for (uint256 i = 0; i < totalCount; i++) {
      for (uint256 j = i + 1; j < totalCount; j++) {
        if (allIds[i] != 0 && allIds[j] != 0) {
          assertNotEq(allIds[i], allIds[j], "Found duplicate settlement ID in pagination");
        }
      }
    }
  }

  //--------------------------------------------------------------------------------
  // Edge Cases
  //--------------------------------------------------------------------------------
  function test_getAllMethods_WithValidPageSizeBoundaries_Succeed() public view {
    // Test minimum valid page size (2)
    (uint256[] memory ids1,) = dvpHelper.getSettlementsByToken(address(dvp), usdc, 0, 2);
    (uint256[] memory ids2,) = dvpHelper.getSettlementsByInvolvedParty(address(dvp), alice, 0, 2);
    (uint256[] memory ids3,) =
      dvpHelper.getSettlementsByTokenType(address(dvp), DeliveryVersusPaymentV1HelperV1.TokenType.ERC20, 0, 2);

    // Test maximum valid page size (200)
    (uint256[] memory ids4,) = dvpHelper.getSettlementsByToken(address(dvp), usdc, 0, 200);
    (uint256[] memory ids5,) = dvpHelper.getSettlementsByInvolvedParty(address(dvp), alice, 0, 200);
    (uint256[] memory ids6,) =
      dvpHelper.getSettlementsByTokenType(address(dvp), DeliveryVersusPaymentV1HelperV1.TokenType.ERC20, 0, 200);

    // All should succeed (not revert)
    assertGe(ids1.length, 0);
    assertGe(ids2.length, 0);
    assertGe(ids3.length, 0);
    assertGe(ids4.length, 0);
    assertGe(ids5.length, 0);
    assertGe(ids6.length, 0);
  }

  function test_helperMethods_WithEmptyDVPContract_ReturnEmpty() public {
    // Deploy a fresh DVP contract with no settlements
    DeliveryVersusPaymentV1 emptyDVP = new DeliveryVersusPaymentV1();

    (uint256[] memory ids1,) = dvpHelper.getSettlementsByToken(address(emptyDVP), usdc, 0, 5);
    (uint256[] memory ids2,) = dvpHelper.getSettlementsByInvolvedParty(address(emptyDVP), alice, 0, 5);
    (uint256[] memory ids3,) =
      dvpHelper.getSettlementsByTokenType(address(emptyDVP), DeliveryVersusPaymentV1HelperV1.TokenType.ERC20, 0, 5);

    assertEq(ids1.length, 0);
    assertEq(ids2.length, 0);
    assertEq(ids3.length, 0);
  }

  //--------------------------------------------------------------------------------
  // computeNettedFlows Tests
  //--------------------------------------------------------------------------------
  function test_computeNettedFlows_ERC20Chain_GeneratesMinimalAndCreatesAndExecutes() public {
    // Create a settlement with a USDC chain that nets down
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](3);
    flows[0] = _createERC20Flow(alice, bob, usdc, 100);
    flows[1] = _createERC20Flow(bob, charlie, usdc, 70);
    flows[2] = _createERC20Flow(charlie, alice, usdc, 20);

    // Generate minimal netted flows via helper
    IDeliveryVersusPaymentV1.Flow[] memory netted = dvpHelper.computeNettedFlows(flows);

    // Expect 2 netted transfers: Alice->Bob 30, Alice->Charlie 50 (order is deterministic by helper)
    assertEq(netted.length, 2, "Expected two netted flows for USDC");
    assertEq(netted[0].token, usdc);
    assertFalse(netted[0].isNFT);
    assertEq(netted[0].from, alice);
    assertEq(netted[0].to, bob);
    assertEq(netted[0].amountOrId, 30);

    assertEq(netted[1].token, usdc);
    assertFalse(netted[1].isNFT);
    assertEq(netted[1].from, alice);
    assertEq(netted[1].to, charlie);
    assertEq(netted[1].amountOrId, 50);

    // Create settlement with netted flows, this will run the validation
    uint256 settlementId = dvp.createSettlement(flows, netted, "USDC chain", _getFutureTimestamp(7 days), false);

    // Approvals (allowances for ERC20 and DVP approvals by from-parties)
    _approveERC20(alice, usdc, 100);
    _approveERC20(bob, usdc, 70);
    _approveERC20(charlie, usdc, 20);

    uint256[] memory ids = _getSettlementIdArray(settlementId);
    vm.prank(alice);
    dvp.approveSettlements(ids);
    vm.prank(bob);
    dvp.approveSettlements(ids);
    vm.prank(charlie);
    dvp.approveSettlements(ids);

    assertTrue(dvp.isSettlementApproved(settlementId));

    // Snapshot balances and execute
    uint256 aBefore = AssetToken(usdc).balanceOf(alice);
    uint256 bBefore = AssetToken(usdc).balanceOf(bob);
    uint256 cBefore = AssetToken(usdc).balanceOf(charlie);

    dvp.executeSettlement(settlementId);

    // Check net deltas: Alice -80, Bob +30, Charlie +50
    assertEq(AssetToken(usdc).balanceOf(alice), aBefore - 80);
    assertEq(AssetToken(usdc).balanceOf(bob), bBefore + 30);
    assertEq(AssetToken(usdc).balanceOf(charlie), cBefore + 50);

    // isSettled set
    (,,,,, bool isSettled,,) = dvp.getSettlement(settlementId);
    assertTrue(isSettled);
  }

  //--------------------------------------------------------------------------------
  // computeNetRequirements Tests
  //--------------------------------------------------------------------------------
  function test_computeNetRequirementsForParty_ERC20Chain_NetApprovalsForDebtorOnly() public {
    // Same USDC chain as computeNettedFlows test
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](3);
    flows[0] = _createERC20Flow(alice, bob, usdc, 100);
    flows[1] = _createERC20Flow(bob, charlie, usdc, 70);
    flows[2] = _createERC20Flow(charlie, alice, usdc, 20);

    uint256 settlementId = dvp.createSettlement(flows, "USDC chain reqs", _getFutureTimestamp(7 days), false);

    // Alice net outgoing = 80, Bob net = -30, Charlie net = -50
    {
      DeliveryVersusPaymentV1HelperV1.NetRequirement memory netRequirement =
        dvpHelper.computeNetRequirementsForParty(address(dvp), settlementId, alice);
      assertEq(netRequirement.ethRequiredNet, 0);
      assertEq(netRequirement.erc20Tokens.length, 1);
      assertEq(netRequirement.erc20Tokens[0], usdc);
      assertEq(netRequirement.erc20NetRequired.length, 1);
      assertEq(netRequirement.erc20NetRequired[0], 80);
    }
    {
      DeliveryVersusPaymentV1HelperV1.NetRequirement memory netRequirement =
        dvpHelper.computeNetRequirementsForParty(address(dvp), settlementId, bob);
      assertEq(netRequirement.ethRequiredNet, 0);
      assertEq(netRequirement.erc20Tokens.length, 0);
      assertEq(netRequirement.erc20NetRequired.length, 0);
    }
    {
      DeliveryVersusPaymentV1HelperV1.NetRequirement memory netRequirement =
        dvpHelper.computeNetRequirementsForParty(address(dvp), settlementId, charlie);
      assertEq(netRequirement.ethRequiredNet, 0);
      assertEq(netRequirement.erc20Tokens.length, 0);
      assertEq(netRequirement.erc20NetRequired.length, 0);
    }
  }

  function test_computeNetRequirementsForParty_ETHChain_NetDepositsOnly() public {
    // ETH chain: A->B 10, B->C 4, C->A 3 => A owes 7, B owes 0, C owes 0
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](3);
    flows[0] = _createETHFlow(alice, bob, 10 ether);
    flows[1] = _createETHFlow(bob, charlie, 4 ether);
    flows[2] = _createETHFlow(charlie, alice, 3 ether);

    uint256 settlementId = dvp.createSettlement(flows, "ETH chain reqs", _getFutureTimestamp(7 days), false);

    {
      DeliveryVersusPaymentV1HelperV1.NetRequirement memory netRequirement =
        dvpHelper.computeNetRequirementsForParty(address(dvp), settlementId, alice);
      assertEq(netRequirement.ethRequiredNet, 7 ether);
      assertEq(netRequirement.erc20Tokens.length, 0);
      assertEq(netRequirement.erc20NetRequired.length, 0);
    }
    {
      DeliveryVersusPaymentV1HelperV1.NetRequirement memory netRequirement =
        dvpHelper.computeNetRequirementsForParty(address(dvp), settlementId, bob);
      assertEq(netRequirement.ethRequiredNet, 0);
      assertEq(netRequirement.erc20Tokens.length, 0);
      assertEq(netRequirement.erc20NetRequired.length, 0);
    }
    {
      DeliveryVersusPaymentV1HelperV1.NetRequirement memory netRequirement =
        dvpHelper.computeNetRequirementsForParty(address(dvp), settlementId, charlie);
      assertEq(netRequirement.ethRequiredNet, 0);
      assertEq(netRequirement.erc20Tokens.length, 0);
      assertEq(netRequirement.erc20NetRequired.length, 0);
    }
  }

  function test_computeNetRequirementsForParty_Mixed_IgnoresNFTAndReturnsOnlyPositiveNets() public {
    // Flows:
    // USDC: A->B 50, C->A 30, B->C 20 => Nets: A owes 20, C owes 10, B receives 30
    // ETH:  A->B 2e18, B->C 2e18, C->A 3e18 => Nets: A receives 1e18, B neutral, C owes 1e18
    // NFT:  A->C Daisy (ignored for net requirements)
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](7);
    flows[0] = _createERC20Flow(alice, bob, usdc, 50);
    flows[1] = _createETHFlow(alice, bob, 2 ether);
    flows[2] = _createNFTFlow(alice, charlie, nftCat, NFT_CAT_DAISY);
    flows[3] = _createERC20Flow(charlie, alice, usdc, 30);
    flows[4] = _createERC20Flow(bob, charlie, usdc, 20);
    flows[5] = _createETHFlow(bob, charlie, 2 ether);
    flows[6] = _createETHFlow(charlie, alice, 3 ether);

    uint256 settlementId = dvp.createSettlement(flows, "mixed reqs", _getFutureTimestamp(7 days), false);

    // Alice: ETH 0 (net receiver), USDC owes 20
    {
      DeliveryVersusPaymentV1HelperV1.NetRequirement memory netRequirement =
        dvpHelper.computeNetRequirementsForParty(address(dvp), settlementId, alice);
      assertEq(netRequirement.ethRequiredNet, 0, "Expected no ETH owed by alice");
      assertEq(netRequirement.erc20Tokens.length, 1, "Expected one token owed by alice");
      assertEq(netRequirement.erc20Tokens[0], usdc, "Expected USDC owed by alice");
      assertEq(netRequirement.erc20NetRequired[0], 20, "Expected 20 USDC owed by alice");
    }
    // Bob: ETH 0, no ERC20 owed
    {
      DeliveryVersusPaymentV1HelperV1.NetRequirement memory netRequirement =
        dvpHelper.computeNetRequirementsForParty(address(dvp), settlementId, bob);
      assertEq(netRequirement.ethRequiredNet, 0, "Expected no ETH owed by bob");
      assertEq(netRequirement.erc20Tokens.length, 0, "Expected no tokens owed by bob");
      assertEq(netRequirement.erc20NetRequired.length, 0, "Expected no amounts owed by bob");
    }
    // Charlie: ETH owes 1 ether, USDC owes 10
    {
      DeliveryVersusPaymentV1HelperV1.NetRequirement memory netRequirement =
        dvpHelper.computeNetRequirementsForParty(address(dvp), settlementId, charlie);
      assertEq(netRequirement.ethRequiredNet, 1 ether, "Expected 1 ETH owed by charlie");
      assertEq(netRequirement.erc20Tokens.length, 1, "Expected one token owed by charlie");
      assertEq(netRequirement.erc20Tokens[0], usdc, "Expected USDC owed by charlie");
      assertEq(netRequirement.erc20NetRequired.length, 1, "Expected one amount entry for charlie");
      assertEq(netRequirement.erc20NetRequired[0], 10, "Expected 10 USDC owed by charlie");
    }
  }

  function test_computeNetRequirementsForParties_Mixed_EquivalentTocomputeNetRequirementsForParty() public {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](7);
    flows[0] = _createERC20Flow(alice, bob, usdc, 50);
    flows[1] = _createETHFlow(alice, bob, 2 ether);
    flows[2] = _createNFTFlow(alice, charlie, nftCat, NFT_CAT_DAISY);
    flows[3] = _createERC20Flow(charlie, alice, usdc, 30);
    flows[4] = _createERC20Flow(bob, charlie, usdc, 20);
    flows[5] = _createETHFlow(bob, charlie, 2 ether);
    flows[6] = _createETHFlow(charlie, alice, 3 ether);

    uint256 settlementId = dvp.createSettlement(flows, "mixed reqs", _getFutureTimestamp(7 days), false);

    // Prepare parties list
    address[] memory parties = new address[](3);
    parties[0] = alice;
    parties[1] = bob;
    parties[2] = charlie;
    DeliveryVersusPaymentV1HelperV1.NetRequirement[] memory netRequirements =
      dvpHelper.computeNetRequirementsForParties(address(dvp), settlementId, parties);

    assertEq(netRequirements.length, 3);
    _assertEqNetRequirement(
      netRequirements[0], dvpHelper.computeNetRequirementsForParty(address(dvp), settlementId, alice)
    );
    _assertEqNetRequirement(
      netRequirements[1], dvpHelper.computeNetRequirementsForParty(address(dvp), settlementId, bob)
    );
    _assertEqNetRequirement(
      netRequirements[2], dvpHelper.computeNetRequirementsForParty(address(dvp), settlementId, charlie)
    );
  }
}
