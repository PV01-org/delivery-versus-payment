// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {DeliveryVersusPaymentV1HelperV1} from "../src/dvp/V1/DeliveryVersusPaymentV1HelperV1.sol";

contract Deploy is Script {
  function run() external returns (DeliveryVersusPaymentV1HelperV1) {
    vm.startBroadcast();
    DeliveryVersusPaymentV1HelperV1 dvp = new DeliveryVersusPaymentV1HelperV1();
    vm.stopBroadcast();
    return dvp;
  }
}
