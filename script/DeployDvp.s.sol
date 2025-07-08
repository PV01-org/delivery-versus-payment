// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {DeliveryVersusPaymentV1} from "../src/dvp/V1/DeliveryVersusPaymentV1.sol";

contract Deploy is Script {
  function run() external returns (DeliveryVersusPaymentV1) {
    vm.startBroadcast();
    DeliveryVersusPaymentV1 dvp = new DeliveryVersusPaymentV1();
    vm.stopBroadcast();
    return dvp;
  }
}
