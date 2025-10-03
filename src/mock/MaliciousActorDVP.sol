// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IDeliveryVersusPaymentV1} from "./IDeliveryVersusPaymentV1.sol";

/**
 * @dev Actor wallet that attempts to re-enter various DVP functions during a transfer of ETH.
 */
contract MaliciousActorDVP {
  IDeliveryVersusPaymentV1 private dvp;
  uint256 private targetSettlementId;

  enum ReentrancyMode {
    NoReentrancy,
    WithdrawETH,
    ApproveSettlement,
    ExecuteSettlement,
    RevokeApproval
  }

  ReentrancyMode private reentrancyMode;

  constructor(IDeliveryVersusPaymentV1 _dvp) {
    dvp = _dvp;
    reentrancyMode = ReentrancyMode.NoReentrancy;
  }

  function setTargetSettlementId(uint256 _targetSettlementId) external {
    targetSettlementId = _targetSettlementId;
  }

  function setReentrancyMode(ReentrancyMode _mode) external {
    reentrancyMode = _mode;
  }

  receive() external payable {
    if (reentrancyMode == ReentrancyMode.NoReentrancy) {
      //------------------------------------------------------------------------------
      // Do nothing
      //------------------------------------------------------------------------------
      //
    } else if (reentrancyMode == ReentrancyMode.WithdrawETH) {
      //------------------------------------------------------------------------------
      // Re-enter withdrawETH()
      //------------------------------------------------------------------------------
      dvp.withdrawETH(targetSettlementId);
      //
    } else if (reentrancyMode == ReentrancyMode.ApproveSettlement) {
      //------------------------------------------------------------------------------
      // Re-enter approveSettlements()
      //------------------------------------------------------------------------------
      uint256[] memory ids = new uint256[](1);
      ids[0] = targetSettlementId;
      // Forward any ETH, in case the settlement required a deposit
      dvp.approveSettlements{value: msg.value}(ids);
      //
    } else if (reentrancyMode == ReentrancyMode.ExecuteSettlement) {
      //------------------------------------------------------------------------------
      // Re-enter executeSettlement()
      //------------------------------------------------------------------------------
      dvp.executeSettlement(targetSettlementId);
      //
    } else if (reentrancyMode == ReentrancyMode.RevokeApproval) {
      //------------------------------------------------------------------------------
      // Re-enter revokeApprovals()
      //------------------------------------------------------------------------------
      uint256[] memory ids = new uint256[](1);
      ids[0] = targetSettlementId;
      dvp.revokeApprovals(ids);
      //
    }
  }
}
