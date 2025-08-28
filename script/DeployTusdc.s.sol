// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {AssetToken} from "../src/mock/AssetToken.sol";

contract Deploy is Script {
  function run() external returns (AssetToken) {
    vm.startBroadcast();
    AssetToken assetToken = new AssetToken("Test USDC", "TUSDC", 18);
    vm.stopBroadcast();
    return assetToken;
  }
}
