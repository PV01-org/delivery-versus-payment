import {
  SnapshotRestorer,
  takeSnapshot,
} from "@nomicfoundation/hardhat-network-helpers";
import { DeliveryVersusPaymentV1 } from "@typechain/contracts/dvp/V1/DeliveryVersusPaymentV1";
import { DeliveryVersusPaymentV1HelperV1 } from "@typechain/contracts/dvp/V1/DeliveryVersusPaymentV1HelperV1";
import { AssetToken } from "@typechain/contracts/mock/AssetToken";
import { NFT } from "@typechain/contracts/mock/NFT";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import {
  DeliveryVersusPaymentV1__factory,
  DeliveryVersusPaymentV1HelperV1__factory,
} from "../typechain/factories/contracts/dvp/V1";
import { getAccounts } from "./utils/accounts";
import { CUSTOM_ERRORS } from "./utils/customErrors";
import { findEvent } from "./utils/events";
import { Timestamps } from "./utils/timestamps";
import { createNFT, createToken } from "./utils/tokens";
import {
  buildFlowsERC20Simple,
  buildFlowsEthSimple,
  buildFlowsMixedLarge,
  buildFlowsNftSimple,
} from "./utils/deliveryVersusPaymentSetup";
import { Account } from "./utils/types";

enum TokenType {
  Ether, // flows with token == address(0)
  ERC20, // flows with token != address(0) and isNFT === false
  NFT, // flows with token != address(0) and isNFT === true
}

let _deployer: Account;
let _alice: Account;
let _bob: Account;
let _charlie: Account;
let _dave: Account;

let _snapshot: SnapshotRestorer;
let _usdcToken: AssetToken;
let _daiToken: AssetToken;
let _nftCatToken: NFT;
let _nftDogToken: NFT;
let _usdc: string;
let _dai: string;
let _nftCat: string;
let _nftDog: string;
let _eth: string;
let _dvp: DeliveryVersusPaymentV1;
let _dvpAddress: string;
let _dvpHelper: DeliveryVersusPaymentV1HelperV1;

const _timestamps = new Timestamps();

// Some token amount constants (using bigint literal style)
const TOKEN_AMOUNT_LARGE_6_DECIMALS = 100_000_000_000_000n;
const TOKEN_AMOUNT_LARGE_18_DECIMALS = 100_000_000_000_000_000_000_000_000n;
const TOKEN_AMOUNT_SMALL_6_DECIMALS = 5_000_000_000n;
const TOKEN_AMOUNT_SMALL_18_DECIMALS = 4_000_000_000_000_000_000_000n;

// NFT ids
const NFT_CAT_DAISY = 1;
const NFT_CAT_BUTTONS = 2;
const NFT_DOG_FIDO = 1;
const NFT_DOG_TOBY = 2;

describe(`DeliveryVersusPaymentV1HelperV1 on network:${network.name}`, function () {
  before(async function () {
    // Get accounts
    [_deployer, _alice, _bob, _charlie, _dave] = await getAccounts();
    _deployer.description = "deployer";
    _alice.description = "alice";
    _bob.description = "bob";
    _charlie.description = "charlie";
    _dave.description = "dave";

    // Deploy main DVP contract
    _dvp = await new DeliveryVersusPaymentV1__factory(
      _deployer.wallet
    ).deploy();
    _dvpAddress = await _dvp.getAddress();
    await _dvp.waitForDeployment();

    // Deploy helper contract pointing to the DVP contract
    _dvpHelper = await new DeliveryVersusPaymentV1HelperV1__factory(
      _deployer.wallet
    ).deploy();
    await _dvpHelper.waitForDeployment();

    // Create ERC20 tokens
    _usdcToken = await createToken(_deployer, "USDC", "USDC", 6);
    _usdc = await _usdcToken.getAddress();
    _daiToken = await createToken(_deployer, "DAI", "DAI", 18);
    _dai = await _daiToken.getAddress();

    // Create NFT contracts
    _nftCatToken = await createNFT(_deployer, "NFT-Cat", "NFT-Cat");
    _nftCat = await _nftCatToken.getAddress();
    _nftDogToken = await createNFT(_deployer, "NFT-Dog", "NFT-Dog");
    _nftDog = await _nftDogToken.getAddress();

    // ETH is represented as the zero address
    _eth = ethers.ZeroAddress;

    // Mint tokens to parties
    await _usdcToken
      .connect(_deployer.wallet)
      .mint(_alice.address, TOKEN_AMOUNT_LARGE_6_DECIMALS);
    await _usdcToken
      .connect(_deployer.wallet)
      .mint(_bob.address, TOKEN_AMOUNT_LARGE_6_DECIMALS);
    await _usdcToken
      .connect(_deployer.wallet)
      .mint(_charlie.address, TOKEN_AMOUNT_LARGE_6_DECIMALS);

    await _daiToken
      .connect(_deployer.wallet)
      .mint(_alice.address, TOKEN_AMOUNT_LARGE_18_DECIMALS);
    await _daiToken
      .connect(_deployer.wallet)
      .mint(_bob.address, TOKEN_AMOUNT_LARGE_18_DECIMALS);
    await _daiToken
      .connect(_deployer.wallet)
      .mint(_charlie.address, TOKEN_AMOUNT_LARGE_18_DECIMALS);

    // Mint NFTs
    // Alice gets two cats
    await _nftCatToken
      .connect(_deployer.wallet)
      .mint(_alice.address, NFT_CAT_DAISY);
    await _nftCatToken
      .connect(_deployer.wallet)
      .mint(_alice.address, NFT_CAT_BUTTONS);
    // Charlie gets two dogs
    await _nftDogToken
      .connect(_deployer.wallet)
      .mint(_charlie.address, NFT_DOG_FIDO);
    await _nftDogToken
      .connect(_deployer.wallet)
      .mint(_charlie.address, NFT_DOG_TOBY);

    // Set up a FlowBuilder object to pass into our helper functions
    const fb = {
      _alice,
      _bob,
      _charlie,
      _dave,
      _usdc,
      _eth,
      _dai,
      _nftCat,
      _nftDog,
      NFT_CAT_DAISY,
      NFT_CAT_BUTTONS,
      NFT_DOG_FIDO,
      TOKEN_AMOUNT_SMALL_6_DECIMALS,
      TOKEN_AMOUNT_SMALL_18_DECIMALS,
    };

    // Create settlements of various types. Each settlement type uses flows that are constructed to be uniquely identifiable.
    // We create 30 settlements for each type: mixed, NFT-only, ERC20-only, Ether-only.
    const settlementsToCreatePerType = 30;
    const cutoff = _timestamps.nowPlusDays(7);
    for (let i = 0; i < settlementsToCreatePerType; i++) {
      // Mixed flows (contain multiple token types)
      {
        const flows = buildFlowsMixedLarge(fb);
        const tx = await _dvp
          .connect(_alice.wallet)
          .createSettlement(flows, `Type mixed ${i}`, cutoff, false);
        const receipt = await tx.wait();
        const event = findEvent(receipt, "SettlementCreated");
        expect(event).to.exist;
      }
      // NFT-only flows
      {
        const flows = buildFlowsNftSimple(fb);
        const tx = await _dvp
          .connect(_alice.wallet)
          .createSettlement(flows, `Type NFT ${i}`, cutoff, false);
        const receipt = await tx.wait();
        const event = findEvent(receipt, "SettlementCreated");
        expect(event).to.exist;
      }
      // ERC20-only flows
      {
        const flows = buildFlowsERC20Simple(fb);
        const tx = await _dvp
          .connect(_alice.wallet)
          .createSettlement(flows, `Type ERC20 ${i}`, cutoff, false);
        const receipt = await tx.wait();
        const event = findEvent(receipt, "SettlementCreated");
        expect(event).to.exist;
      }
      // Ether-only flows
      {
        const flows = buildFlowsEthSimple(fb);
        const tx = await _dvp
          .connect(_alice.wallet)
          .createSettlement(flows, `Type Ether ${i}`, cutoff, false);
        const receipt = await tx.wait();
        const event = findEvent(receipt, "SettlementCreated");
        expect(event).to.exist;
      }
    }
    _snapshot = await takeSnapshot();
  });

  beforeEach(async function () {
    await _snapshot.restore();
  });

  describe("[Function] getTokenTypes()", function () {
    it("[Case 1] Should succeed returning three token types with the expected id and names", async function () {
      const types = await _dvpHelper.getTokenTypes();
      expect(types.length).to.equal(3);
      expect(types[0].id).to.equal(0);
      expect(types[0].name).to.equal("Ether");
      expect(types[1].id).to.equal(1);
      expect(types[1].name).to.equal("ERC20");
      expect(types[2].id).to.equal(2);
      expect(types[2].name).to.equal("NFT");
    });
  });

  describe("[Function] getSettlementsByToken()", function () {
    it("[Case 1] Should succeed returning settlements that include the given token (USDC)", async function () {
      const pageSize = 5;
      const { settlementIds } = await _dvpHelper.getSettlementsByToken(
        _dvpAddress,
        _usdc,
        0,
        pageSize
      );
      expect(settlementIds.length).to.be.greaterThan(0);
      // Verify that each settlement includes at least one flow with token == _usdc
      for (const id of settlementIds) {
        const settlement = await _dvp.getSettlement(id);
        const hasToken = settlement.flows.some((flow) => flow.token === _usdc);
        expect(hasToken).to.be.true;
      }
    });

    it("[Case 2] Should succeed returning an empty array when no settlements match the token", async function () {
      const randomToken = ethers.Wallet.createRandom().address;
      const pageSize = 5;
      const { settlementIds, nextCursor } =
        await _dvpHelper.getSettlementsByToken(
          _dvpAddress,
          randomToken,
          0,
          pageSize
        );
      expect(settlementIds.length).to.equal(0);
      expect(nextCursor).to.equal(0);
    });

    it("[Case 3] Should revert for an invalid pageSize", async function () {
      await expect(
        _dvpHelper.getSettlementsByToken(_dvpAddress, _usdc, 0, 1)
      ).to.be.revertedWithCustomError(
        _dvpHelper,
        CUSTOM_ERRORS.DeliveryVersusPaymentHelper.InvalidPageSize
      );
      await expect(
        _dvpHelper.getSettlementsByToken(_dvpAddress, _usdc, 0, 201)
      ).to.be.revertedWithCustomError(
        _dvpHelper,
        CUSTOM_ERRORS.DeliveryVersusPaymentHelper.InvalidPageSize
      );
    });
  });

  describe("[Function] getSettlementsByInvolvedParty()", function () {
    it("[Case 1] Should succeed returning settlements involving the given party", async function () {
      const pageSize = 5;
      const { settlementIds } = await _dvpHelper.getSettlementsByInvolvedParty(
        _dvpAddress,
        _bob.address,
        0,
        pageSize
      );
      expect(settlementIds.length).to.be.greaterThan(0);
      for (const id of settlementIds) {
        const settlement = await _dvp.getSettlement(id);
        const involved = settlement.flows.some(
          (flow) => flow.from === _bob.address || flow.to === _bob.address
        );
        expect(involved).to.be.true;
      }
    });

    it("[Case 2] Should succeed returning an empty array when the party is not involved in any settlement", async function () {
      const randomParty = ethers.Wallet.createRandom().address;
      const pageSize = 5;
      const { settlementIds } = await _dvpHelper.getSettlementsByInvolvedParty(
        _dvpAddress,
        randomParty,
        0,
        pageSize
      );
      expect(settlementIds.length).to.equal(0);
    });

    it("[Case 3] Should revert for an invalid pageSize", async function () {
      await expect(
        _dvpHelper.getSettlementsByInvolvedParty(
          _dvpAddress,
          _bob.address,
          0,
          1
        )
      ).to.be.revertedWithCustomError(
        _dvpHelper,
        CUSTOM_ERRORS.DeliveryVersusPaymentHelper.InvalidPageSize
      );
      await expect(
        _dvpHelper.getSettlementsByInvolvedParty(
          _dvpAddress,
          _bob.address,
          0,
          201
        )
      ).to.be.revertedWithCustomError(
        _dvpHelper,
        CUSTOM_ERRORS.DeliveryVersusPaymentHelper.InvalidPageSize
      );
    });
  });

  describe("[Function] getSettlementsByTokenType()", function () {
    it("[Case 1] Should succeed returning settlements for token type Ether", async function () {
      const pageSize = 5;
      const { settlementIds } = await _dvpHelper.getSettlementsByTokenType(
        _dvpAddress,
        TokenType.Ether,
        0,
        pageSize
      );
      expect(settlementIds.length).to.be.greaterThan(0);
      for (const id of settlementIds) {
        const settlement = await _dvp.getSettlement(id);
        // Ether flows have token equal to _eth (i.e. ZeroAddress)
        const hasEtherFlow = settlement.flows.some(
          (flow) => flow.token === _eth
        );
        expect(hasEtherFlow).to.be.true;
      }
    });

    it("[Case 2] Should succeed returning settlements for token type ERC20", async function () {
      const pageSize = 5;
      const { settlementIds } = await _dvpHelper.getSettlementsByTokenType(
        _dvpAddress,
        TokenType.ERC20,
        0,
        pageSize
      );
      expect(settlementIds.length).to.be.greaterThan(0);
      for (const id of settlementIds) {
        const settlement = await _dvp.getSettlement(id);
        // ERC20 flows have a non-zero token and isNFT === false
        const hasERC20Flow = settlement.flows.some(
          (flow) => flow.token !== _eth && flow.isNFT === false
        );
        expect(hasERC20Flow).to.be.true;
      }
    });

    it("[Case 3] Should succeed returning settlements for token type NFT", async function () {
      const pageSize = 5;
      const { settlementIds } = await _dvpHelper.getSettlementsByTokenType(
        _dvpAddress,
        TokenType.NFT,
        0,
        pageSize
      );
      expect(settlementIds.length).to.be.greaterThan(0);
      for (const id of settlementIds) {
        const settlement = await _dvp.getSettlement(id);
        // NFT flows have a non-zero token and isNFT === true
        const hasNFTFlow = settlement.flows.some(
          (flow) => flow.token !== _eth && flow.isNFT === true
        );
        expect(hasNFTFlow).to.be.true;
      }
    });

    it("[Case 4] Should revert for an invalid pageSize", async function () {
      await expect(
        _dvpHelper.getSettlementsByTokenType(_dvpAddress, TokenType.Ether, 0, 1)
      ).to.be.revertedWithCustomError(
        _dvpHelper,
        CUSTOM_ERRORS.DeliveryVersusPaymentHelper.InvalidPageSize
      );
      await expect(
        _dvpHelper.getSettlementsByTokenType(
          _dvpAddress,
          TokenType.Ether,
          0,
          201
        )
      ).to.be.revertedWithCustomError(
        _dvpHelper,
        CUSTOM_ERRORS.DeliveryVersusPaymentHelper.InvalidPageSize
      );
    });

    it("[Case 5] Should correctly use a non-zero startCursor for pagination (ERC20)", async function () {
      const pageSize = 5;
      // First call with startCursor = 0 to get the nextCursor
      const { settlementIds, nextCursor } =
        await _dvpHelper.getSettlementsByTokenType(
          _dvpAddress,
          TokenType.ERC20,
          0,
          pageSize
        );
      expect(settlementIds.length).to.be.greaterThan(0);

      // Only proceed if there is a valid nextCursor (non-zero)
      if (nextCursor !== 0n) {
        const { settlementIds: nextPageIds } =
          await _dvpHelper.getSettlementsByTokenType(
            _dvpAddress,
            TokenType.ERC20,
            nextCursor,
            pageSize
          );
        // Verify that the call with a nonzero startCursor returns an array (could be empty or not)
        expect(nextPageIds).to.be.an("array");
      }
    });
  });

  describe("[Process] Pagination behavior", function () {
    it("[Case 1] Should succeed with paginate results for getSettlementsByToken", async function () {
      const pageSize = 3;
      let allIds: number[] = [];
      let cursor = 0n;
      do {
        const { settlementIds, nextCursor } =
          await _dvpHelper.getSettlementsByToken(
            _dvpAddress,
            _usdc,
            cursor,
            pageSize
          );
        allIds = allIds.concat(settlementIds.map((id) => Number(id)));
        cursor = nextCursor;
      } while (cursor !== 0n);
      expect(allIds.length).to.be.greaterThan(0);
      // Ensure there are no duplicate IDs.
      const uniqueIds = Array.from(new Set(allIds));
      expect(uniqueIds.length).to.equal(allIds.length);
    });

    it("[Case 2] Should succeed with paginate results for getSettlementsByInvolvedParty", async function () {
      const pageSize = 4;
      let allIds: number[] = [];
      let cursor = 0n;
      do {
        const { settlementIds, nextCursor } =
          await _dvpHelper.getSettlementsByInvolvedParty(
            _dvpAddress,
            _alice.address,
            cursor,
            pageSize
          );
        allIds = allIds.concat(settlementIds.map((id) => Number(id)));
        cursor = nextCursor;
      } while (cursor !== 0n);
      expect(allIds.length).to.be.greaterThan(0);
      const uniqueIds = Array.from(new Set(allIds));
      expect(uniqueIds.length).to.equal(allIds.length);
    });
  });
});
