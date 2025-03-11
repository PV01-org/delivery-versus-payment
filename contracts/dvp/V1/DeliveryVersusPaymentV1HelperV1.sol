// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./IDeliveryVersusPaymentV1.sol";

/**
 * @title DeliveryVersusPaymentV1HelperV1
 * @dev Provides view helper functions to page through settlements using a cursor-based approach.
 * Created by https://pv0.one.
 * It allows filtering by token address, by involved party, or by token type (Ether, ERC20, or NFT).
 * Each function accepts a DVP contract, a starting cursor and a pageSize and returns matching settlement
 * IDs along with a nextCursor (which is the settlement ID to use as the starting cursor in the next call).
 * These functions are not intended to be used in state-changing transactions, they are intended for
 * use by clients as read-only views of the DeliveryVersusPaymentV1 contract.
 * It is clients resposibility to ensure that the DVP contract is valid.
 */
contract DeliveryVersusPaymentV1HelperV1 {
  error InvalidPageSize();

  modifier validPageSize(uint256 pageSize) {
    if (pageSize < 2 || pageSize > 200) revert InvalidPageSize();
    _;
  }

  enum TokenType {
    Ether, // Settlements containing any flow with Ether (token == address(0))
    ERC20, // Settlements containing any flow with an ERC20 token (token != address(0) && isNFT == false)
    NFT // Settlements containing any flow with an NFT (token != address(0) && isNFT == true)
  }

  // A struct for returning token type information.
  struct TokenTypeInfo {
    uint8 id;
    string name;
  }

  //------------------------------------------------------------------------------
  // External
  //------------------------------------------------------------------------------
  /**
   * @dev Returns a list of token types as (id, name) pairs.
   */
  function getTokenTypes() external pure returns (TokenTypeInfo[] memory) {
    TokenTypeInfo[] memory types = new TokenTypeInfo[](3);
    types[0] = TokenTypeInfo(uint8(TokenType.Ether), "Ether");
    types[1] = TokenTypeInfo(uint8(TokenType.ERC20), "ERC20");
    types[2] = TokenTypeInfo(uint8(TokenType.NFT), "NFT");
    return types;
  }

  /**
   * @dev Returns a page of settlement IDs that include at least one flow with the given token address.
   * @param dvpAddress The address of the Delivery verus Payment contract.
   * @param token The token address used to filter settlements.
   * @param startCursor The settlement ID to start from (0 means start at the latest settlement).
   * @param pageSize The number of matching settlement IDs to return, valid values 2 to 200.
   * @return settlementIds An array of matching settlement IDs (up to pageSize in length).
   * @return nextCursor The settlement ID to use as the startCursor on the next call (or 0 if finished).
   */
  function getSettlementsByToken(
    address dvpAddress,
    address token,
    uint256 startCursor,
    uint256 pageSize
  ) external view validPageSize(pageSize) returns (uint256[] memory settlementIds, uint256 nextCursor) {
    // true indicates filtering on flows' token field.
    return _getPagedSettlementIds(dvpAddress, startCursor, pageSize, true, token);
  }

  /**
   * @dev Returns a page of settlement IDs that involve the given party (as sender or receiver).
   * @param dvpAddress The address of the Delivery verus Payment contract.
   * @param involvedParty The address to filter settlements by.
   * @param startCursor The settlement ID to start from (0 means start at the latest settlement).
   * @param pageSize The number of matching settlement IDs to return, valid values 2 to 200.
   * @return settlementIds An array of matching settlement IDs (up to pageSize in length).
   * @return nextCursor The settlement ID to use as the startCursor on the next call (or 0 if finished).
   */
  function getSettlementsByInvolvedParty(
    address dvpAddress,
    address involvedParty,
    uint256 startCursor,
    uint256 pageSize
  ) external view validPageSize(pageSize) returns (uint256[] memory settlementIds, uint256 nextCursor) {
    // false indicates filtering on flows' from/to fields.
    return _getPagedSettlementIds(dvpAddress, startCursor, pageSize, false, involvedParty);
  }

  /**
   * @dev Returns a page of settlement IDs that include at least one flow matching the specified token type.
   * Token type can be Ether, ERC20, or NFT.
   * @param dvpAddress The address of the Delivery verus Payment contract.
   * @param tokenType The token type to filter settlements by.
   * @param startCursor The settlement ID to start from (0 means start at the latest settlement).
   * @param pageSize The number of matching settlement IDs to return, valid values 2 to 200.
   * @return settlementIds An array of matching settlement IDs (up to pageSize in length).
   * @return nextCursor The settlement ID to use as the startCursor on the next call (or 0 if finished).
   */
  function getSettlementsByTokenType(
    address dvpAddress,
    TokenType tokenType,
    uint256 startCursor,
    uint256 pageSize
  ) external view validPageSize(pageSize) returns (uint256[] memory settlementIds, uint256 nextCursor) {
    return _getPagedSettlementIdsByType(dvpAddress, startCursor, pageSize, tokenType);
  }

  //------------------------------------------------------------------------------
  // Internal
  //------------------------------------------------------------------------------
  /**
   * @dev Internal helper that iterates backwards over settlement IDs to accumulate matching ones for address-based filters.
   * @param dvpAddress The address of the Delivery verus Payment contract.
   * @param startCursor The settlement ID to start from (0 means use dvp.settlementIdCounter()).
   * @param pageSize The number of matching settlement IDs to accumulate.
   * @param isTokenFilter. If true, filtering is done on flows' token field (comparing to filterAddress).
   * If false, filtering is done on flows' from/to fields (comparing to filterAddress).
   * @param filterAddress The address to filter by.
   * @return matchingIds An array of matching settlement IDs (of length <= pageSize).
   * @return nextCursor The settlement ID from which to continue in the next call (or 0 if there are no more).
   */
  function _getPagedSettlementIds(
    address dvpAddress,
    uint256 startCursor,
    uint256 pageSize,
    bool isTokenFilter,
    address filterAddress
  ) internal view returns (uint256[] memory matchingIds, uint256 nextCursor) {
    IDeliveryVersusPaymentV1 dvp = IDeliveryVersusPaymentV1(dvpAddress);
    uint256 current = startCursor == 0 ? dvp.settlementIdCounter() : startCursor;
    uint256[] memory temp = new uint256[](pageSize);
    uint256 count = 0;

    while (current > 0 && count < pageSize) {
      try dvp.getSettlement(current) returns (
        string memory,
        uint256,
        IDeliveryVersusPaymentV1.Flow[] memory flows,
        bool,
        bool
      ) {
        bool found = false;
        for (uint256 i = 0; i < flows.length; i++) {
          if (isTokenFilter) {
            if (flows[i].token == filterAddress) {
              found = true;
              break;
            }
          } else {
            if (flows[i].from == filterAddress || flows[i].to == filterAddress) {
              found = true;
              break;
            }
          }
        }
        if (found) {
          temp[count] = current;
          count++;
        }
      } catch {
        // settlement cannot be retrieved, skip it.
      }
      current--;
    }
    nextCursor = current;
    matchingIds = new uint256[](count);
    for (uint256 j = 0; j < count; j++) {
      matchingIds[j] = temp[j];
    }
  }

  /**
   * @dev Internal helper that iterates backwards over settlement IDs to accumulate matching ones based on token type.
   * @param dvpAddress The address of the Delivery verus Payment contract.
   * @param startCursor The settlement ID to start from (0 means use dvp.settlementIdCounter()).
   * @param pageSize The number of matching settlement IDs to accumulate.
   * @param tokenType The token type filter (Ether, ERC20, or NFT).
   * @return matchingIds An array of matching settlement IDs (of length <= pageSize).
   * @return nextCursor The settlement ID from which to continue in the next call (or 0 if there are no more).
   */
  function _getPagedSettlementIdsByType(
    address dvpAddress,
    uint256 startCursor,
    uint256 pageSize,
    TokenType tokenType
  ) internal view returns (uint256[] memory matchingIds, uint256 nextCursor) {
    IDeliveryVersusPaymentV1 dvp = IDeliveryVersusPaymentV1(dvpAddress);
    uint256 current = startCursor == 0 ? dvp.settlementIdCounter() : startCursor;
    uint256[] memory temp = new uint256[](pageSize);
    uint256 count = 0;

    while (current > 0 && count < pageSize) {
      try dvp.getSettlement(current) returns (
        string memory,
        uint256,
        IDeliveryVersusPaymentV1.Flow[] memory flows,
        bool,
        bool
      ) {
        if (_matchesTokenType(flows, tokenType)) {
          temp[count] = current;
          count++;
        }
      } catch {
        // settlement cannot be retrieved, skip it.
      }
      current--;
    }
    nextCursor = current;
    matchingIds = new uint256[](count);
    for (uint256 j = 0; j < count; j++) {
      matchingIds[j] = temp[j];
    }
  }

  /**
   * @dev Internal pure function to determine if any flow in the provided array matches the specified token type.
   * @param flows An array of flows to check.
   * @param tokenType The token type filter.
   * @return True if at least one flow matches the token type, false otherwise.
   */
  function _matchesTokenType(
    IDeliveryVersusPaymentV1.Flow[] memory flows,
    TokenType tokenType
  ) internal pure returns (bool) {
    for (uint256 i = 0; i < flows.length; i++) {
      // For Ether, the token address must be zero.
      if (tokenType == TokenType.Ether && flows[i].token == address(0)) {
        return true;
      }
      // For ERC20, the token address must be non-zero and isNFT must be false.
      if (tokenType == TokenType.ERC20 && flows[i].token != address(0) && !flows[i].isNFT) {
        return true;
      }
      // For NFT, the token address must be non-zero and isNFT must be true.
      if (tokenType == TokenType.NFT && flows[i].token != address(0) && flows[i].isNFT) {
        return true;
      }
    }
    return false;
  }
}
