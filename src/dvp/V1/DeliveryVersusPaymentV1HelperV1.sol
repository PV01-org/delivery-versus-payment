// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
██████╗░██╗░░░██╗██████╗░███████╗░█████╗░░██████╗██╗░░░██╗░░░██╗░░██╗██╗░░░██╗███████╗
██╔══██╗██║░░░██║██╔══██╗██╔════╝██╔══██╗██╔════╝╚██╗░██╔╝░░░╚██╗██╔╝╚██╗░██╔╝╚════██║
██║░░██║╚██╗░██╔╝██████╔╝█████╗░░███████║╚█████╗░░╚████╔╝░░░░░╚███╔╝░░╚████╔╝░░░███╔═╝
██║░░██║░╚████╔╝░██╔═══╝░██╔══╝░░██╔══██║░╚═══██╗░░╚██╔╝░░░░░░██╔██╗░░░╚██╔╝░░██╔══╝░░
██████╔╝░░╚██╔╝░░██║░░░░░███████╗██║░░██║██████╔╝░░░██║░░░██╗██╔╝╚██╗░░░██║░░░███████╗
╚═════╝░░░░╚═╝░░░╚═╝░░░░░╚══════╝╚═╝░░╚═╝╚═════╝░░░░╚═╝░░░╚═╝╚═╝░░╚═╝░░░╚═╝░░░╚══════╝
 */

import "./IDeliveryVersusPaymentV1.sol";

/**
 * @title DeliveryVersusPaymentV1HelperV1
 * @dev Provides view helper functions to page through settlements using a cursor-based approach.
 * Created by https://pv0.one. UI implemented at https://dvpeasy.xyz.
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

  // Asset key and metadata used for netting computation
  struct AssetMeta {
    address token; // token address or address(0) for ETH
    bool isNFT;    // true for ERC-721
    uint256 id;    // tokenId for NFT; 0 for fungibles (ERC20/ETH)
  }

  // Net requirement result struct
  struct NetRequirement {
    uint256 ethRequiredNet;          // Net ETH the party must send with approveSettlements (0 if net receiver or neutral)
    address[] erc20Tokens;           // Distinct ERC20 token addresses for which approvals may be needed
    uint256[] erc20NetRequired;      // Minimal ERC20 allowance amounts (net outgoing per token; 0 entries are omitted)
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

  /**
   * @dev Computes an optimized netted array of flows for a given settlement.
   * It minimizes fungible transfers per token (including ETH) by netting balances per party and
   * pairing debtors and creditors greedily. NFTs are handled per tokenId with at most one transfer.
   *
   * This is a simple, ready-to-use greedy optimizer meant for clients to call directly (on-chain or via SDKs).
   * While it typically produces a small number of transfers and good gas characteristics, for best possible
   * optimization (e.g., strictly minimal number of fungible transfers across complex graphs), we suggest
   * computing netting off-chain using a MILP/LP solver and then submitting the result to executeSettlementNetted.
   *
   * Reverts if the underlying DVP.getSettlement() call fails (e.g., non-existent settlement).
   * @param dvpAddress Address of the DVP contract.
   * @param settlementId ID of the target settlement.
   * @return netted An array of flows representing a netted execution plan equivalent to the original.
   */
  function computeNettedFlows(
    address dvpAddress,
    uint256 settlementId
  ) external view returns (IDeliveryVersusPaymentV1.Flow[] memory netted) {
    IDeliveryVersusPaymentV1 dvp = IDeliveryVersusPaymentV1(dvpAddress);
    // Retrieve flows (bubble up any revert from DVP)
    (, , IDeliveryVersusPaymentV1.Flow[] memory flows, , ) = dvp.getSettlement(settlementId);
    return computeNettedFlows(dvpAddress, flows);
  }
  /**
   * @dev Computes an optimized netted array of flows from the given flows.
   * This function minimizes fungible transfers per token (including ETH) by netting balances per party
   * and pairing debtors and creditors greedily. NFTs are handled per tokenId with at most one transfer.
   *
   * @param dvpAddress The address of the Delivery Versus Payment contract.
   * @param flows An array of flows to be optimized into a netted execution plan.
   *
   * @return netted An array of flows representing a netted execution plan equivalent to the original.
   */
  function computeNettedFlows(
    address dvpAddress,
    IDeliveryVersusPaymentV1.Flow[] memory flows
  ) external view returns (IDeliveryVersusPaymentV1.Flow[] memory netted) {
    uint256 lengthFlows = flows.length;
    // Upper bound for netted flows is original length
    netted = new IDeliveryVersusPaymentV1.Flow[](lengthFlows);
    uint256 outCount = 0;

    // 1) Build unique parties and asset metas
    address[] memory parties = new address[](lengthFlows * 2);
    uint256 partyCount = 0;
    AssetMeta[] memory assets = new AssetMeta[](lengthFlows);
    uint256 assetCount = 0;

    for (uint256 i = 0; i < lengthFlows; i++) {
      IDeliveryVersusPaymentV1.Flow memory f = flows[i];
      // Parties
      uint256 idxFrom = _indexOfAddress(parties, partyCount, f.from);
      if (idxFrom == type(uint256).max) {
        parties[partyCount++] = f.from;
      }
      uint256 idxTo = _indexOfAddress(parties, partyCount, f.to);
      if (idxTo == type(uint256).max) {
        parties[partyCount++] = f.to;
      }
      // Assets
      AssetMeta memory meta = AssetMeta({token: f.token, isNFT: f.isNFT, id: f.isNFT ? f.amountOrId : 0});
      uint256 aIdx = _indexOfAssetMeta(assets, assetCount, meta);
      if (aIdx == type(uint256).max) {
        assets[assetCount++] = meta;
      }
    }

    // 2) Build balances matrix [assetCount][partyCount] flattened
    int256[] memory balances = new int256[](assetCount * partyCount);

    for (uint256 i = 0; i < lengthFlows; i++) {
      IDeliveryVersusPaymentV1.Flow memory f = flows[i];
      AssetMeta memory meta = AssetMeta({token: f.token, isNFT: f.isNFT, id: f.isNFT ? f.amountOrId : 0});
      uint256 k = _indexOfAssetMeta(assets, assetCount, meta);
      uint256 pFrom = _indexOfAddress(parties, partyCount, f.from);
      uint256 pTo = _indexOfAddress(parties, partyCount, f.to);
      int256 delta = f.isNFT ? int256(1) : int256(f.amountOrId);
      uint256 idxA = k * partyCount + pFrom;
      uint256 idxB = k * partyCount + pTo;
      balances[idxA] -= delta;
      balances[idxB] += delta;
    }

    // 3) Convert balances per asset into netted flows
    for (uint256 k = 0; k < assetCount; k++) {
      if (assets[k].isNFT) {
        // Find -1 and +1 parties (there should be at most one of each per tokenId)
        address fromAddr = address(0);
        address toAddr = address(0);
        uint256 base = k * partyCount;
        for (uint256 p = 0; p < partyCount; p++) {
          int256 b = balances[base + p];
          if (b == -1) {
            fromAddr = parties[p];
          } else if (b == 1) {
            toAddr = parties[p];
          }
        }
        if (fromAddr != address(0) && toAddr != address(0)) {
          netted[outCount++] = IDeliveryVersusPaymentV1.Flow({
            token: assets[k].token,
            isNFT: true,
            from: fromAddr,
            to: toAddr,
            amountOrId: assets[k].id
          });
        }
        // else fully canceled path -> no transfer needed
      } else {
        outCount = _appendNettedFungible(
          assets[k].token,
          parties,
          balances,
          k * partyCount,
          partyCount,
          netted,
          outCount
        );
      }
    }

    // 4) Trim output array without using assembly (copy to exact-sized array)
    IDeliveryVersusPaymentV1.Flow[] memory trimmed = new IDeliveryVersusPaymentV1.Flow[](outCount);
    for (uint256 t = 0; t < outCount; t++) {
      trimmed[t] = netted[t];
    }
    return trimmed;
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
        uint256 lengthFlows = flows.length;
        for (uint256 i = 0; i < lengthFlows; i++) {
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
    uint256 lengthFlows = flows.length;
    for (uint256 i = 0; i < lengthFlows; i++) {
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

  // ---- Netting helpers (memory-only) ----
  function _indexOfAddress(address[] memory arr, uint256 length, address a) internal pure returns (uint256) {
    for (uint256 i = 0; i < length; i++) {
      if (arr[i] == a) return i;
    }
    return type(uint256).max;
  }

  function _indexOfAssetMeta(AssetMeta[] memory arr, uint256 length, AssetMeta memory m) internal pure returns (uint256) {
    for (uint256 i = 0; i < length; i++) {
      AssetMeta memory x = arr[i];
      if (x.token == m.token && x.isNFT == m.isNFT && x.id == m.id) {
        return i;
      }
    }
    return type(uint256).max;
  }

  // Appends netted fungible flows for a single asset into `out`, returns new outCount
  function _appendNettedFungible(
    address token,
    address[] memory parties,
    int256[] memory balances,
    uint256 baseIndex, // offset into balances for this asset (k * partyCount)
    uint256 partyCount,
    IDeliveryVersusPaymentV1.Flow[] memory out,
    uint256 outCount
  ) internal pure returns (uint256) {
    uint256[] memory negIdx = new uint256[](partyCount);
    uint256[] memory posIdx = new uint256[](partyCount);
    uint256[] memory negAmt = new uint256[](partyCount);
    uint256[] memory posAmt = new uint256[](partyCount);
    uint256 ni = 0;
    uint256 pj = 0;

    for (uint256 p = 0; p < partyCount; p++) {
      int256 b = balances[baseIndex + p];
      if (b < 0) {
        negIdx[ni] = p;
        negAmt[ni] = uint256(-b);
        ni++;
      } else if (b > 0) {
        posIdx[pj] = p;
        posAmt[pj] = uint256(b);
        pj++;
      }
    }

    uint256 iNeg = 0;
    uint256 jPos = 0;
    while (iNeg < ni && jPos < pj) {
      uint256 x = negAmt[iNeg];
      uint256 y = posAmt[jPos];
      uint256 amt = x < y ? x : y;
      if (amt > 0) {
        out[outCount++] = IDeliveryVersusPaymentV1.Flow({
          token: token,
          isNFT: false,
          from: parties[negIdx[iNeg]],
          to: parties[posIdx[jPos]],
          amountOrId: amt
        });
      }
      if (x <= y) {
        iNeg++;
        if (x < y) {
          posAmt[jPos] = y - x;
        } else {
          jPos++;
        }
      } else {
        jPos++;
        negAmt[iNeg] = x - y;
      }
    }
    return outCount;
  }

  /**
   * @notice Compute minimal per-party requirements for a given settlement.
   * @dev Returns the net ETH a party must deposit (if positive) and the minimal ERC20 approvals per token
   * when executing via a debtor→creditor netted plan (as enforced by DVP.executeSettlementNetted).
   * NFTs are excluded because they require per-tokenId approvals rather than amounts.
   * Reverts if the underlying DVP.getSettlement() call fails.
   * @param dvpAddress Address of the DVP contract.
   * @param settlementId ID of the settlement.
   * @param party Address of the party to compute requirements for.
   * @return result NetRequirement data struct with ETH and ERC20 requirements.
   */
  function computeNetRequirementsForParty(
    address dvpAddress,
    uint256 settlementId,
    address party
  ) external view returns (
    NetRequirement memory result
  ) {
    IDeliveryVersusPaymentV1.Flow[] memory netted = this.computeNettedFlows(dvpAddress, settlementId);
    return _computeNetRequirementsForParty(netted, party);
  }
  /**
  * @notice Compute net requirements for a party from netted flows.
  * @dev Returns the net ETH a party must deposit (if positive) and the minimal ERC20 approvals per token
  * when executing via a debtor→creditor netted plan.
  * NFTs are excluded because they require per-tokenId approvals rather than amounts.
  * @param flows Array of netted flows to analyze.
  * @param party Address of the party to compute requirements for.
  * @return result NetRequirement data struct with ETH and ERC20 requirements.
  */
  function _computeNetRequirementsForParty(IDeliveryVersusPaymentV1.Flow[] memory flows, address party) internal pure returns (
    NetRequirement memory result
  ) {
    for (uint256 i = 0; i < flows.length; i++) {
      IDeliveryVersusPaymentV1.Flow memory f = flows[i];
      if (f.from == party) {
        if (f.token == address(0)) {
          // ETH leg
          result.ethRequiredNet += f.amountOrId;
        } else if (!f.isNFT) {
          // ERC20 leg: accumulate per token net (outgoing only)
          uint256 idx = _indexOfAddress(result.erc20Tokens, result.erc20Tokens.length, f.token);
          if (idx == type(uint256).max) {
            // New token, expand arrays
            uint256 oldLen = result.erc20Tokens.length;
            address[] memory newTokens = new address[](oldLen + 1);
            uint256[] memory newAmounts = new uint256[](oldLen + 1);
            for (uint256 j = 0; j < oldLen; j++) {
              newTokens[j] = result.erc20Tokens[j];
              newAmounts[j] = result.erc20NetRequired[j];
            }
            newTokens[oldLen] = f.token;
            newAmounts[oldLen] = f.amountOrId;
            result.erc20Tokens = newTokens;
            result.erc20NetRequired = newAmounts;
          } else {
            // Existing token, accumulate
            result.erc20NetRequired[idx] += f.amountOrId;
          }
        }
        // NFTs ignored for this computation
      }
    }
  }
  /**
   * @notice Compute minimal per-party requirements for a given settlement for an array of parties.
   * @dev Returns the net ETH each given party must deposit (if positive) and the minimal ERC20 approvals per token
   * when executing via a debtor→creditor netted plan (as enforced by DVP.executeSettlementNetted).
   * NFTs are excluded because they require per-tokenId approvals rather than amounts.
   * Reverts if the underlying DVP.getSettlement() call fails.
   * @param dvpAddress Address of the DVP contract.
   * @param settlementId ID of the settlement.
   * @param parties Array of addresses of the parties to compute requirements for.
   * @return results Array of NetRequirement data structs with ETH and ERC20 requirements for each party.
   */
  function computeNetRequirementsForParties(
    address dvpAddress,
    uint256 settlementId,
    address[] calldata parties
  ) external view returns (
    NetRequirement[] memory results
  ) {
    IDeliveryVersusPaymentV1.Flow[] memory netted = this.computeNettedFlows(dvpAddress, settlementId);

    results = new NetRequirement[](parties.length);
    for (uint256 i = 0; i < parties.length; i++) {
      results[i] = _computeNetRequirementsForParty(netted, parties[i]);
    }
  }

}
