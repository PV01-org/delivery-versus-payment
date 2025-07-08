// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "./TestDvpBase.sol";

/**
 * @title DeliveryVersusPaymentV1InfraTest
 * @notice Tests the "test infrastructure", deployment verification and setup validation.
 */
contract DeliveryVersusPaymentV1InfraTest is TestDvpBase {
  function test_contractDeployment_Succeeds() public view {
    assertTrue(address(dvp) != address(0));
    assertEq(dvp.settlementIdCounter(), 0);
  }

  function test_helperContractDeployment_Succeeds() public view {
    assertTrue(address(dvpHelper) != address(0));
  }

  function test_mockTokensDeployment_Succeeds() public view {
    assertTrue(address(usdcToken) != address(0));
    assertTrue(address(daiToken) != address(0));
    assertTrue(address(nftCatToken) != address(0));
    assertTrue(address(nftDogToken) != address(0));

    assertEq(usdcToken.decimals(), 6);
    assertEq(daiToken.decimals(), 18);
    assertEq(nftCatToken.balanceOf(alice), 2);
    assertEq(nftDogToken.balanceOf(charlie), 2);
  }
}
