// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {DeliveryVersusPaymentV1} from "../src/dvp/V1/DeliveryVersusPaymentV1.sol";
import {DeliveryVersusPaymentV1HelperV1} from "../src/dvp/V1/DeliveryVersusPaymentV1HelperV1.sol";
import {IDeliveryVersusPaymentV1} from "../src/dvp/V1/IDeliveryVersusPaymentV1.sol";
import {AssetToken} from "../src/mock/AssetToken.sol";
import {AssetTokenThatReverts} from "../src/mock/AssetTokenThatReverts.sol";
import {NFT} from "../src/mock/NFT.sol";
import {MaliciousActorDVP} from "../src/mock/MaliciousActorDVP.sol";
import {MaliciousTokenDVP} from "../src/mock/MaliciousTokenDVP.sol";
import {SanctionsList} from "../src/mock/SanctionsList.sol";
import {IDeliveryVersusPaymentV1 as IMockDVP} from "../src/mock/IDeliveryVersusPaymentV1.sol";

/**
 * @title TestDvpBase
 * @notice Base test contract providing common setup, utilities, and helper functions for all DVP test contracts.
 * Contains mock token deployments, test actor setup, and reusable flow creation helpers.
 */
contract TestDvpBase is Test {
  // Test actors
  address public deployer;
  address public alice;
  address public bob;
  address public charlie;
  address public dave;
  address public eve;

  // Core contracts
  DeliveryVersusPaymentV1 public dvp;
  DeliveryVersusPaymentV1HelperV1 public dvpHelper;

  // Token contracts
  AssetToken public usdcToken;
  AssetToken public usdtToken;
  AssetToken public daiToken;
  AssetTokenThatReverts public assetTokenThatReverts;
  NFT public nftCatToken;
  NFT public nftDogToken;
  MaliciousTokenDVP public maliciousToken;
  SanctionsList public sanctionsList;

  // Token addresses
  address public usdc;
  address public usdt;
  address public dai;
  address public nftCat;
  address public nftDog;
  address public maliciousTokenAddress;
  address public eth = address(0);

  // Malicious actor contract
  MaliciousActorDVP public maliciousActor;

  // Token amounts
  uint256 public constant TOKEN_AMOUNT_LARGE_6_DECIMALS = 100_000_000_000_000;
  uint256 public constant TOKEN_AMOUNT_LARGE_18_DECIMALS = 100_000_000_000_000_000_000_000_000;
  uint256 public constant TOKEN_AMOUNT_SMALL_6_DECIMALS = 50_000_000; // 50
  uint256 public constant TOKEN_AMOUNT_SMALL_18_DECIMALS = 40_000_000_000_000_000_000; // 40
  uint256 public constant TOKEN_AMOUNT_FOR_REVERT_STRING = 1;
  uint256 public constant TOKEN_AMOUNT_FOR_REVERT_CUSTOM_ERROR = 2;
  uint256 public constant TOKEN_AMOUNT_FOR_REVERT_PANIC = 3;
  uint256 public constant TOKEN_AMOUNT_FOR_REVERT_DEFAULT_MESSAGE = 4;

  // Token amounts for AssetTokenThatReverts.sol have special meaning and trigger different revert styles
  uint256 public constant AMOUNT_FOR_REVERT_REASON_STRING = 1;
  uint256 public constant AMOUNT_FOR_REVERT_CUSTOM_ERROR = 2;
  uint256 public constant AMOUNT_FOR_REVERT_PANIC = 3;
  uint256 public constant AMOUNT_FOR_REVERT_NO_MESSAGE = 4;

  // NFT IDs
  uint256 public constant NFT_CAT_DAISY = 1;
  uint256 public constant NFT_CAT_BUTTONS = 2;
  uint256 public constant NFT_DOG_FIDO = 1;
  uint256 public constant NFT_DOG_TOBY = 2;

  // Settlement reference
  string public constant SETTLEMENT_REF = "Test Reference";
  uint256 public constant NOT_A_SETTLEMENT_ID = 666;

  function setUp() public virtual {
    // Set up test actors
    deployer = address(this);
    alice = makeAddr("alice");
    bob = makeAddr("bob");
    charlie = makeAddr("charlie");
    dave = makeAddr("dave");
    eve = makeAddr("eve");

    // Give test actors some ETH
    vm.deal(alice, 100 ether);
    vm.deal(bob, 100 ether);
    vm.deal(charlie, 100 ether);
    vm.deal(dave, 100 ether);
    vm.deal(eve, 100 ether);

    // Deploy core contracts
    dvp = new DeliveryVersusPaymentV1();
    dvpHelper = new DeliveryVersusPaymentV1HelperV1();

    // Deploy ERC20 tokens
    usdcToken = new AssetToken("USDC", "USDC", 6);
    usdc = address(usdcToken);

    usdtToken = new AssetToken("USDT", "USDT", 6);
    usdt = address(usdtToken);

    daiToken = new AssetToken("DAI", "DAI", 18);
    dai = address(daiToken);

    // Deploy revert token
    assetTokenThatReverts = new AssetTokenThatReverts("RevertToken", "REV", 6);

    // Deploy NFT contracts
    nftCatToken = new NFT("NFT-Cat", "NFT-Cat");
    nftCat = address(nftCatToken);

    nftDogToken = new NFT("NFT-Dog", "NFT-Dog");
    nftDog = address(nftDogToken);

    // Deploy malicious contracts
    maliciousToken = new MaliciousTokenDVP("MaliciousToken", "MAL", IMockDVP(address(dvp)));
    maliciousTokenAddress = address(maliciousToken);

    maliciousActor = new MaliciousActorDVP(IMockDVP(address(dvp)));

    sanctionsList = new SanctionsList(deployer);

    // Mint tokens to test actors
    _mintTokensToActors();
    _mintNFTsToActors();
  }

  function _mintTokensToActors() internal {
    // Mint ERC20 tokens
    address[4] memory actors = [alice, bob, charlie, dave];

    for (uint256 i = 0; i < actors.length; i++) {
      usdcToken.mint(actors[i], TOKEN_AMOUNT_LARGE_6_DECIMALS);
      usdtToken.mint(actors[i], TOKEN_AMOUNT_LARGE_6_DECIMALS);
      daiToken.mint(actors[i], TOKEN_AMOUNT_LARGE_18_DECIMALS);
      maliciousToken.mint(actors[i], TOKEN_AMOUNT_LARGE_18_DECIMALS);
    }
  }

  function _mintNFTsToActors() internal {
    // Alice gets two cats
    nftCatToken.mint(alice, NFT_CAT_DAISY);
    nftCatToken.mint(alice, NFT_CAT_BUTTONS);

    // Charlie gets two dogs
    nftDogToken.mint(charlie, NFT_DOG_FIDO);
    nftDogToken.mint(charlie, NFT_DOG_TOBY);
  }

  // Helper functions for creating flows
  function _createERC20Flow(
    address from,
    address to,
    address token,
    uint256 amount
  ) internal pure returns (IDeliveryVersusPaymentV1.Flow memory) {
    return IDeliveryVersusPaymentV1.Flow({token: token, isNFT: false, from: from, to: to, amountOrId: amount});
  }

  function _createETHFlow(
    address from,
    address to,
    uint256 amount
  ) internal pure returns (IDeliveryVersusPaymentV1.Flow memory) {
    return IDeliveryVersusPaymentV1.Flow({token: address(0), isNFT: false, from: from, to: to, amountOrId: amount});
  }

  function _createNFTFlow(
    address from,
    address to,
    address token,
    uint256 tokenId
  ) internal pure returns (IDeliveryVersusPaymentV1.Flow memory) {
    return IDeliveryVersusPaymentV1.Flow({token: token, isNFT: true, from: from, to: to, amountOrId: tokenId});
  }

  // Helper to create simple mixed flows (ERC20 + ETH + NFT)
  function _createMixedFlows() internal view returns (IDeliveryVersusPaymentV1.Flow[] memory) {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](4);
    flows[0] = _createERC20Flow(alice, bob, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    flows[1] = _createETHFlow(bob, charlie, TOKEN_AMOUNT_SMALL_18_DECIMALS);
    flows[2] = _createERC20Flow(charlie, alice, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);
    flows[3] = _createNFTFlow(alice, charlie, nftCat, NFT_CAT_DAISY);
    return flows;
  }

  // Helper to create simple ERC20-only flows
  function _createERC20Flows() internal view returns (IDeliveryVersusPaymentV1.Flow[] memory) {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](2);
    flows[0] = _createERC20Flow(alice, bob, usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS);
    flows[1] = _createERC20Flow(bob, charlie, dai, TOKEN_AMOUNT_SMALL_18_DECIMALS);
    return flows;
  }

  // Helper to create simple ETH-only flows
  function _createETHFlows() internal view returns (IDeliveryVersusPaymentV1.Flow[] memory) {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](2);
    flows[0] = _createETHFlow(alice, bob, TOKEN_AMOUNT_SMALL_18_DECIMALS);
    flows[1] = _createETHFlow(bob, charlie, TOKEN_AMOUNT_SMALL_18_DECIMALS / 2);
    return flows;
  }

  // Helper to create simple NFT-only flows
  function _createNFTFlows() internal view returns (IDeliveryVersusPaymentV1.Flow[] memory) {
    IDeliveryVersusPaymentV1.Flow[] memory flows = new IDeliveryVersusPaymentV1.Flow[](2);
    flows[0] = _createNFTFlow(alice, bob, nftCat, NFT_CAT_DAISY);
    flows[1] = _createNFTFlow(charlie, alice, nftDog, NFT_DOG_FIDO);
    return flows;
  }

  // Helper to create mixed flows (ERC20 + ETH + NFT) for netting
  function _createMixedFlowsForNetting()
    internal
    view
    returns (IDeliveryVersusPaymentV1.Flow[] memory flows, IDeliveryVersusPaymentV1.Flow[] memory nettedFlows, uint256 cutoff, uint256 ethA, uint256 ethB, uint256 ethC)
  {
    // Original flows (6 total):
    // ETH:  A->B 10e18, B->C 4e18, C->A 3e18
    // USDC: A->C 50,      C->B 20
    // NFT:  A->C Cat Daisy (id=1)
    flows = new IDeliveryVersusPaymentV1.Flow[](6);
    uint256 tenEth = TOKEN_AMOUNT_SMALL_18_DECIMALS; // 40e18 from base, but we want explicit 10e18 here.
    // Adjust: Use fixed values for clarity
    tenEth = 10 ether;

    flows[0] = _createETHFlow(alice, bob, tenEth);
    flows[1] = _createETHFlow(bob, charlie, 4 ether);
    flows[2] = _createETHFlow(charlie, alice, 3 ether);

    flows[3] = _createERC20Flow(alice, charlie, usdc, 50);
    flows[4] = _createERC20Flow(charlie, bob, usdc, 20);

    flows[5] = _createNFTFlow(alice, charlie, nftCat, NFT_CAT_DAISY);

    // Build netted flows (equivalent):
    // ETH nets to: A->C 7, B->C 4
    // USDC nets to: A->B 20, A->C 30
    // NFT unchanged: A->C Daisy
    nettedFlows = new IDeliveryVersusPaymentV1.Flow[](5);
    nettedFlows[0] = _createETHFlow(alice, bob, 6 ether);
    nettedFlows[1] = _createETHFlow(alice, charlie, 1 ether);
    nettedFlows[2] = _createERC20Flow(alice, bob, usdc, 20);
    nettedFlows[3] = _createERC20Flow(alice, charlie, usdc, 30);
    nettedFlows[4] = _createNFTFlow(alice, charlie, nftCat, NFT_CAT_DAISY);

    cutoff = _getFutureTimestamp(7 days);

    // ETH deposits required per original
    ethA = 7 ether; // A must deposit 7 ether
    ethB = 0 ether; // B must deposit 0 ether
    ethC = 0 ether; // C must deposit 0 ether
  }

  // Helper to approve ERC20 tokens for DVP
  function _approveERC20(address owner, address token, uint256 amount) internal {
    vm.prank(owner);
    AssetToken(token).approve(address(dvp), amount);
  }

  // Helper to approve NFT for DVP
  function _approveNFT(address owner, address token, uint256 tokenId) internal {
    vm.prank(owner);
    NFT(token).approve(address(dvp), tokenId);
  }

  // Helper to approve all NFTs for DVP
  function _approveAllNFTs(address owner, address token) internal {
    vm.prank(owner);
    NFT(token).setApprovalForAll(address(dvp), true);
  }

  // Helper to get an array with a single invalid settlementId
  function _getInvalidSettlementIdArray() internal pure returns (uint256[] memory arr) {
    arr = new uint256[](1);
    arr[0] = NOT_A_SETTLEMENT_ID;
  }

  // Helper to turn a single settlementId into an array of one element
  function _getSettlementIdArray(uint256 settlementId) internal pure returns (uint256[] memory arr) {
    arr = new uint256[](1);
    arr[0] = settlementId;
  }

  function _getFutureTimestamp(uint256 secondsInFuture) internal view returns (uint256) {
    return block.timestamp + secondsInFuture;
  }

  function _advanceTime(uint256 secondsToMove) internal {
    vm.warp(block.timestamp + secondsToMove);
  }
}
