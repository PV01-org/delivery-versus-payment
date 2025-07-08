// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IDeliveryVersusPaymentV1} from "./IDeliveryVersusPaymentV1.sol";
import "@openzeppelin/contracts-v5-2-0/token/ERC20/ERC20.sol";

/**
 * @dev ERC20 that attempts to re-enter DVP `executeSettlement` during a `transferFrom` call.
 */
contract MaliciousTokenDVP is ERC20 {
  IDeliveryVersusPaymentV1 private dvp;
  uint256 private targetSettlementId;

  constructor(string memory name_, string memory symbol_, IDeliveryVersusPaymentV1 _dvp) ERC20(name_, symbol_) {
    dvp = _dvp;
  }

  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }

  function setTargetSettlementId(uint256 _targetSettlementId) external {
    targetSettlementId = _targetSettlementId;
  }

  function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
    // Normal transfer
    _transfer(sender, recipient, amount);

    // Attempt re-entrancy into DVP
    dvp.executeSettlement(targetSettlementId);

    return true;
  }
}
