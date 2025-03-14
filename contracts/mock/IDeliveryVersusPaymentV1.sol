// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IDeliveryVersusPaymentV1 {
  function approveSettlements(uint256[] calldata settlementIds) external payable;

  function withdrawETH(uint256 settlementId) external;

  function executeSettlement(uint256 settlementId) external;

  function revokeApprovals(uint256[] calldata settlementIds) external;
}
