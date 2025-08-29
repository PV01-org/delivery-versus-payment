// SPDX-License-Identifier: UNLICENSED
// Chainalysis sanctions list oracle https://go.chainalysis.com/chainalysis-oracle-docs.html
pragma solidity 0.8.30;

/**
 * @title ISanctionsList
 * @dev Interface that a sanctions screening contract exposes to consumers
 */
interface ISanctionsList {
  /**
   * @dev Returns true if the given address is sanctioned, false otherwise.
   */
  function isSanctioned(address addr) external view returns (bool);
}
