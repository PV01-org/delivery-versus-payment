// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {TestDvpBase} from "./TestDvpBase.sol";
import {IDeliveryVersusPaymentV1} from "../src/dvp/V1/IDeliveryVersusPaymentV1.sol";
import {DeliveryVersusPaymentV1} from "../src/dvp/V1/DeliveryVersusPaymentV1.sol";
import {DeliveryVersusPaymentV1HelperV1} from "../src/dvp/V1/DeliveryVersusPaymentV1HelperV1.sol";

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
    uint128 cutoff = _getFutureTimestamp(7 days);

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
      (,, IDeliveryVersusPaymentV1.Flow[] memory flows,,) = dvp.getSettlement(returnedIds[i]);
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
      (,, IDeliveryVersusPaymentV1.Flow[] memory flows,,) = dvp.getSettlement(returnedIds[i]);
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
      (,, IDeliveryVersusPaymentV1.Flow[] memory flows,,) = dvp.getSettlement(returnedIds[i]);
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
      (,, IDeliveryVersusPaymentV1.Flow[] memory flows,,) = dvp.getSettlement(returnedIds[i]);
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
      (,, IDeliveryVersusPaymentV1.Flow[] memory flows,,) = dvp.getSettlement(returnedIds[i]);
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

  function test_getSettlementsByTokenType_WithMismatchedType_FiltersCorrectly() public {
    // Create a settlement with ONLY ERC20 flows
    IDeliveryVersusPaymentV1.Flow[] memory erc20OnlyFlows = new IDeliveryVersusPaymentV1.Flow[](1);
    erc20OnlyFlows[0] = _createERC20Flow(alice, bob, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 erc20SettlementId = dvp.createSettlement(erc20OnlyFlows, "ERC20 Only Settlement", cutoff, false);

    // Search for NFT type - should NOT find the ERC20-only settlement
    uint256 pageSize = 200;
    (uint256[] memory nftIds,) =
      dvpHelper.getSettlementsByTokenType(address(dvp), DeliveryVersusPaymentV1HelperV1.TokenType.NFT, 0, pageSize);

    // Verify that the ERC20-only settlement is NOT in the NFT results
    bool foundERC20Settlement = false;
    for (uint256 i = 0; i < nftIds.length; i++) {
      if (nftIds[i] == erc20SettlementId) {
        foundERC20Settlement = true;
        break;
      }
    }
    assertFalse(foundERC20Settlement, "ERC20-only settlement should not appear in NFT search results");

    // Similarly, create an NFT-only settlement
    IDeliveryVersusPaymentV1.Flow[] memory nftOnlyFlows = new IDeliveryVersusPaymentV1.Flow[](1);
    nftOnlyFlows[0] = _createNFTFlow(alice, bob, nftCat, NFT_CAT_DAISY);
    uint256 nftSettlementId = dvp.createSettlement(nftOnlyFlows, "NFT Only Settlement", cutoff, false);

    // Search for Ether type - should NOT find the NFT-only settlement
    (uint256[] memory etherIds,) =
      dvpHelper.getSettlementsByTokenType(address(dvp), DeliveryVersusPaymentV1HelperV1.TokenType.Ether, 0, pageSize);

    bool foundNFTSettlement = false;
    for (uint256 i = 0; i < etherIds.length; i++) {
      if (etherIds[i] == nftSettlementId) {
        foundNFTSettlement = true;
        break;
      }
    }
    assertFalse(foundNFTSettlement, "NFT-only settlement should not appear in Ether search results");
  }

  function test_helperMethods_WithSettlementGapsDueToErrors_HandleGracefully() public {
    // Create a settlement, then create a large gap in settlement IDs by incrementing the counter
    // This simulates settlements that might have been deleted or are corrupted
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](1);
    flows[0] = _createERC20Flow(alice, bob, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    uint128 cutoff = _getFutureTimestamp(7 days);
    uint256 validSettlementId = dvp.createSettlement(flows, "Valid Settlement", cutoff, false);

    // Now query with a cursor set to a non-existent settlement ID (one past the last valid one)
    // This tests the catch block when getSettlement fails on invalid IDs
    uint256 pageSize = 5;
    uint256 startCursor = validSettlementId + 1000; // Way past any valid settlement

    // These should not revert, but handle missing settlements gracefully
    (uint256[] memory ids1, uint256 cursor1) = dvpHelper.getSettlementsByToken(address(dvp), usdc, startCursor, pageSize);
    (uint256[] memory ids2, uint256 cursor2) =
      dvpHelper.getSettlementsByInvolvedParty(address(dvp), alice, startCursor, pageSize);
    (uint256[] memory ids3, uint256 cursor3) = dvpHelper.getSettlementsByTokenType(
      address(dvp), DeliveryVersusPaymentV1HelperV1.TokenType.ERC20, startCursor, pageSize
    );

    // All should handle the gap and continue searching backwards
    assertGe(ids1.length, 0); // May or may not find settlements depending on how far back it searches
    assertGe(ids2.length, 0);
    assertGe(ids3.length, 0);
  }
}
