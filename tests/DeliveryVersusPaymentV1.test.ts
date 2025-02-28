import {
  SnapshotRestorer,
  takeSnapshot,
} from "@nomicfoundation/hardhat-network-helpers";
import {
  DeliveryVersusPaymentV1,
  IDeliveryVersusPaymentV1,
} from "@typechain/contracts/dvp/V1/DeliveryVersusPaymentV1";
import { AssetToken } from "@typechain/contracts/mock/AssetToken";
import { AssetTokenThatReverts } from "@typechain/contracts/mock/AssetTokenThatReverts";
import { MaliciousActorDVP } from "@typechain/contracts/mock/MaliciousActorDVP";
import { MaliciousTokenDVP } from "@typechain/contracts/mock/MaliciousTokenDVP";
import { NFT } from "@typechain/contracts/mock/NFT";
import { SanctionsList } from "@typechain/contracts/mock/SanctionsList";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import { DeliveryVersusPaymentV1__factory } from "../typechain/factories/contracts/dvp/V1/DeliveryVersusPaymentV1__factory";
import {
  MaliciousActorDVP__factory,
  MaliciousTokenDVP__factory,
  SanctionsList__factory,
  AssetTokenThatReverts__factory,
} from "../typechain/factories/contracts/mock/";
import {
  buildFlows,
  buildFlowsComplex,
  buildFlowsCoverage,
  buildFlowsMixed,
  buildFlowsNftComplex,
  buildFlowsNftSimple,
  FlowBuilder,
  getAndCheckPartyStatus,
  moveInTime,
} from "./utils/deliveryVersusPaymentSetup";
import { getAccounts } from "./utils/accounts";
import { CUSTOM_ERRORS } from "./utils/customErrors";
import { findEvent } from "./utils/events";
import { Timestamps } from "./utils/timestamps";
import { createNFT, createToken } from "./utils/tokens";
import { Account } from "./utils/types";

const TOKEN_AMOUNT_LARGE_6_DECIMALS = 100_000_000_000_000n;
const TOKEN_AMOUNT_LARGE_18_DECIMALS = 100_000_000_000_000_000_000_000_000n;
const TOKEN_AMOUNT_SMALL_6_DECIMALS = 5_000_000_000n; // 5000
const TOKEN_AMOUNT_SMALL_18_DECIMALS = 4_000_000_000_000_000_000_000n; // 4000
const TOKEN_AMOUNT_FOR_REVERT_STRING = 1n;
const TOKEN_AMOUNT_FOR_REVERT_CUSTOM_ERROR = 2n;
const TOKEN_AMOUNT_FOR_REVERT_PANIC = 3n;
const TOKEN_AMOUNT_FOR_REVERT_DEFAULT_MESSAGE = 4n;
const SETTLEMENT_REF = "Test Reference";
const NOT_A_SETTLEMENT_ID = 666n;
const NFT_CAT_DAISY = 1;
const NFT_CAT_BUTTONS = 2;
const NFT_DOG_FIDO = 1;
const NFT_DOG_TOBY = 2;
const erc20TransferExceedsAllowance =
  "ERC20: transfer amount exceeds allowance";
const erc20TransferExceedsBalance = "ERC20: transfer amount exceeds balance";
const erc721OperatorQueryForNonexistentToken =
  "ERC721: operator query for nonexistent token";
const erc721TransferCallerNotOwnerNorApproved =
  "ERC721: transfer caller is not owner nor approved";
const revertWithReasonString =
  "AssetTokenThatReverts: transferFrom is disabled";
const _timestamps = new Timestamps();

enum ReentrancyMode {
  NoReentrancy = 0,
  WithdrawETH = 1,
  ExecuteSettlement = 2,
  RevokeApproval = 3,
}

type Flow = IDeliveryVersusPaymentV1.FlowStruct;

let _deployer: Account;
let _alice: Account;
let _bob: Account;
let _charlie: Account;
let _dave: Account;
let _maliciousActor: MaliciousActorDVP;
let _maliciousActorAddress: string;
let _snapshot: SnapshotRestorer;
let _usdcToken: AssetToken;
let _usdtToken: AssetToken;
let _daiToken: AssetToken;
let _revertToken: AssetTokenThatReverts;
let _nftCatToken: NFT;
let _nftDogToken: NFT;
let _maliciousToken: MaliciousTokenDVP;
let _usdc: string;
let _usdt: string;
let _dai: string;
let _revert: string;
let _nftCat: string;
let _nftDog: string;
let _eth: string;
let _maliciousTokenAddress: string;
let _dvp: DeliveryVersusPaymentV1;
let _dvpAddress: string;
let _fb: FlowBuilder;
let _sanctionsList: SanctionsList;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

describe(`DeliveryVersusPaymentV1 Network:${network.name}`, async () => {
  before(async function () {
    [_deployer, _alice, _bob, _charlie, _dave] = await getAccounts();
    _deployer.description = "deployer";
    _alice.description = "alice";
    _bob.description = "bob";
    _charlie.description = "charlie";
    _dave.description = "dave";

    // Deploy DVP
    const dvpTx = await new DeliveryVersusPaymentV1__factory(
      _deployer.wallet
    ).deploy();
    await dvpTx.waitForDeployment();
    _dvp = dvpTx;
    _dvpAddress = await _dvp.getAddress();

    // Create tokens
    _usdcToken = await createToken(_deployer, "USDC", "USDC", 6);
    _usdc = await _usdcToken.getAddress();
    _usdtToken = await createToken(_deployer, "USDT", "USDT", 6);
    _usdt = await _usdtToken.getAddress();
    _daiToken = await createToken(_deployer, "DAI", "DAI", 18);
    _dai = await _daiToken.getAddress();

    // Create NFT contracts
    _nftCatToken = await createNFT(_deployer, "NFT-Cat", "NFT-Cat");
    _nftCat = await _nftCatToken.getAddress();
    _nftDogToken = await createNFT(_deployer, "NFT-Dog", "NFT-Dog");
    _nftDog = await _nftDogToken.getAddress();

    // Malicious token
    const maliciousTokenFactory = new MaliciousTokenDVP__factory(
      _deployer.wallet
    );
    _maliciousToken = await maliciousTokenFactory.deploy(
      "MaliciousToken",
      "MAL",
      _dvp
    );
    await _maliciousToken.waitForDeployment();
    _maliciousTokenAddress = await _maliciousToken.getAddress();

    // Malicious actor
    const maliciousActorFactory = new MaliciousActorDVP__factory(
      _deployer.wallet
    );
    _maliciousActor = await maliciousActorFactory.deploy(_dvp);
    await _maliciousActor.waitForDeployment();
    _maliciousActorAddress = await _maliciousActor.getAddress();

    // Asset token that reverts
    const revertTokenFactory = new AssetTokenThatReverts__factory(
      _deployer.wallet
    );
    _revertToken = await revertTokenFactory.deploy("RevertToken", "REV", 6);
    await _revertToken.waitForDeployment();
    _revert = await _revertToken.getAddress();

    // ETH is represented as address(0)
    _eth = ethers.ZeroAddress;

    // Mint large amounts of tokens to most people
    await _usdcToken
      .connect(_deployer.wallet)
      .mint(_alice.address, TOKEN_AMOUNT_LARGE_6_DECIMALS);
    await _usdcToken
      .connect(_deployer.wallet)
      .mint(_bob.address, TOKEN_AMOUNT_LARGE_6_DECIMALS);
    await _usdcToken
      .connect(_deployer.wallet)
      .mint(_charlie.address, TOKEN_AMOUNT_LARGE_6_DECIMALS);

    await _usdtToken
      .connect(_deployer.wallet)
      .mint(_alice.address, TOKEN_AMOUNT_LARGE_6_DECIMALS);
    await _usdtToken
      .connect(_deployer.wallet)
      .mint(_bob.address, TOKEN_AMOUNT_LARGE_6_DECIMALS);
    await _usdtToken
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

    await _maliciousToken
      .connect(_deployer.wallet)
      .mint(_alice.address, TOKEN_AMOUNT_LARGE_18_DECIMALS);
    await _maliciousToken
      .connect(_deployer.wallet)
      .mint(_bob.address, TOKEN_AMOUNT_LARGE_18_DECIMALS);
    await _maliciousToken
      .connect(_deployer.wallet)
      .mint(_charlie.address, TOKEN_AMOUNT_LARGE_18_DECIMALS);

    // Mint NFTs - Alice has two cats
    await _nftCatToken
      .connect(_deployer.wallet)
      .mint(_alice.address, NFT_CAT_DAISY);
    await _nftCatToken
      .connect(_deployer.wallet)
      .mint(_alice.address, NFT_CAT_BUTTONS);

    // Mint NFTs - Charlie has two dogs
    await _nftDogToken
      .connect(_deployer.wallet)
      .mint(_charlie.address, NFT_DOG_FIDO);
    await _nftDogToken
      .connect(_deployer.wallet)
      .mint(_charlie.address, NFT_DOG_TOBY);

    // Flow builder
    _fb = {
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

    // A contract that is not an ERC-20 or ERC-721
    _sanctionsList = await new SanctionsList__factory(_deployer.wallet).deploy(
      _deployer.address
    );

    _snapshot = await takeSnapshot();
  });

  beforeEach(async function () {
    await _snapshot.restore();
  });

  describe("[Function] createSettlement", async () => {
    it("[Case 1] Should succeed with valid flows and future cutoff date", async () => {
      const flows = buildFlows(_fb);
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, false);
      const receipt = await tx.wait();
      const createSettlementEvent = findEvent(receipt, "SettlementCreated");
      expect(createSettlementEvent).not.to.be.undefined;
      const { settlementId, creator } = createSettlementEvent.args;
      expect(settlementId).to.eql(1n);
      expect(creator).to.eql(_alice.address);
    });

    it("[Case 2] Should succeed with empty reference field", async () => {
      const flows = buildFlows(_fb);
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, "", cutoff, false);
      const receipt = await tx.wait();
      const createSettlementEvent = findEvent(receipt, "SettlementCreated");
      expect(createSettlementEvent).not.to.be.undefined;
      const { settlementId } = createSettlementEvent.args;
      expect(settlementId).to.eql(1n);
    });

    it("[Case 3] Should succeed with NFT", async () => {
      const flows = buildFlowsNftSimple(_fb);
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, "", cutoff, false);
      const receipt = await tx.wait();
      const createSettlementEvent = findEvent(receipt, "SettlementCreated");
      expect(createSettlementEvent).not.to.be.undefined;
      const { settlementId } = createSettlementEvent.args;
      expect(settlementId).to.eql(1n);
    });

    it("[Case 4] Should revert if no flows provided", async () => {
      const flows: Flow[] = [];
      await expect(
        _dvp
          .connect(_alice.wallet)
          .createSettlement(
            flows,
            SETTLEMENT_REF,
            _timestamps.nowPlusDays(7),
            false
          )
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.NoFlowsProvided
      );
    });

    it("[Case 5] Should revert if cutoff date is in the past", async () => {
      const flows = buildFlows(_fb);
      await expect(
        _dvp
          .connect(_alice.wallet)
          .createSettlement(
            flows,
            SETTLEMENT_REF,
            _timestamps.nowMinusDays(1),
            false
          )
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.CutoffDatePassed
      );
    });

    it("[Case 6] Should revert if supplied NFT token is really an ERC-20", async () => {
      const flows = buildFlows(_fb);
      flows[0].isNFT = true; // first flow item isn't really an NFT, but user claims it is
      await expect(
        _dvp
          .connect(_alice.wallet)
          .createSettlement(
            flows,
            SETTLEMENT_REF,
            _timestamps.nowPlusDays(7),
            false
          )
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.InvalidERC721Token
      );
    });

    it("[Case 7] Should revert if supplied NFT token is a contract but not ERC-20 or ERC-721", async () => {
      const flows = buildFlows(_fb);
      flows[0].token = await _sanctionsList.getAddress(); // SanctionsList is not an ERC-20 or ERC-721
      flows[0].isNFT = true; // flow item isn't really an NFT, but user claims it is
      await expect(
        _dvp
          .connect(_alice.wallet)
          .createSettlement(
            flows,
            SETTLEMENT_REF,
            _timestamps.nowPlusDays(7),
            false
          )
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.InvalidERC721Token
      );
    });

    it("[Case 8] Should revert if supplied NFT token is really an EoA", async () => {
      const flows = buildFlows(_fb);
      flows[0].token = _alice.address; // Alice is an EoA, not an NFT
      flows[0].isNFT = true;
      await expect(
        _dvp
          .connect(_alice.wallet)
          .createSettlement(
            flows,
            SETTLEMENT_REF,
            _timestamps.nowPlusDays(7),
            false
          )
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.InvalidERC721Token
      );
    });

    it("[Case 9] Should revert if supplied ERC-20 token is really an NFT", async () => {
      const flows = buildFlows(_fb);
      flows[0].token = _nftCat; // first flow item isn't really an NFT, but user claims it is
      await expect(
        _dvp
          .connect(_alice.wallet)
          .createSettlement(
            flows,
            SETTLEMENT_REF,
            _timestamps.nowPlusDays(7),
            false
          )
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.InvalidERC20Token
      );
    });

    it("[Case 10] Should revert if supplied ERC-20 token is a contract but not ERC-20 or ERC-721", async () => {
      const flows = buildFlows(_fb);
      flows[0].token = await _sanctionsList.getAddress(); // SanctionsList is not an ERC-20 or ERC-721
      await expect(
        _dvp
          .connect(_alice.wallet)
          .createSettlement(
            flows,
            SETTLEMENT_REF,
            _timestamps.nowPlusDays(7),
            false
          )
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.InvalidERC20Token
      );
    });

    it("[Case 11] Should revert if supplied ERC-20 token is really an EoA", async () => {
      const flows = buildFlows(_fb);
      flows[0].token = _alice.address; // Alice is an EoA, not an NFT
      await expect(
        _dvp
          .connect(_alice.wallet)
          .createSettlement(
            flows,
            SETTLEMENT_REF,
            _timestamps.nowPlusDays(7),
            false
          )
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.InvalidERC20Token
      );
    });
  });

  describe("[Function] getSettlement", async () => {
    it("[Case 1] Should succeed", async () => {
      const flows = buildFlows(_fb);
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, false);
      const receipt = await tx.wait();
      const createSettlementEvent = findEvent(receipt, "SettlementCreated");
      expect(createSettlementEvent).not.to.be.undefined;

      const [storedRef, storedCutoff, storedFlows, isSettled, isAutoSettled] =
        await _dvp.getSettlement(1n);
      expect(storedRef).to.eql(SETTLEMENT_REF);
      expect(storedCutoff).to.eql(BigInt(cutoff));
      expect(storedFlows.length).to.equal(flows.length);
      expect(isSettled).to.be.false;
      expect(isAutoSettled).to.be.false;
    });

    it("[Case 2] Should succeed with empty reference field", async () => {
      const flows = buildFlows(_fb);
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, "", cutoff, false);
      const receipt = await tx.wait();
      const createSettlementEvent = findEvent(receipt, "SettlementCreated");
      expect(createSettlementEvent).not.to.be.undefined;

      const [storedRef, storedCutoff, storedFlows, isSettled, isAutoSettled] =
        await _dvp.getSettlement(1n);
      expect(storedRef).to.eql("");
      expect(storedCutoff).to.eql(BigInt(cutoff));
      expect(storedFlows.length).to.equal(flows.length);
      expect(isSettled).to.be.false;
      expect(isAutoSettled).to.be.false;
    });

    it("[Case 3] Should revert if settlement does not exist", async () => {
      await expect(
        _dvp.getSettlement(NOT_A_SETTLEMENT_ID)
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.SettlementDoesNotExist
      );
    });

    it("[Case 4] Should succeed for NFT", async () => {
      const flows = buildFlowsNftSimple(_fb);
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, false);
      const receipt = await tx.wait();
      const createSettlementEvent = findEvent(receipt, "SettlementCreated");
      expect(createSettlementEvent).not.to.be.undefined;

      const [storedRef, storedCutoff, storedFlows, isSettled, isAutoSettled] =
        await _dvp.getSettlement(1n);
      expect(storedRef).to.eql(SETTLEMENT_REF);
      expect(storedCutoff).to.eql(BigInt(cutoff));
      expect(storedFlows.length).to.equal(flows.length);
      expect(isSettled).to.be.false;
      expect(isAutoSettled).to.be.false;
      // single flow is NFT of alices cat
      expect(storedFlows[0].token).to.eql(_nftCat);
      expect(storedFlows[0].isNFT).to.be.true; // contract assigned this
      expect(storedFlows[0].from).to.eql(_alice.address);
      expect(storedFlows[0].to).to.eql(_bob.address);
      expect(Number(storedFlows[0].amountOrId)).to.eql(NFT_CAT_DAISY);
    });
  });

  describe("[Function] approveSettlements", async () => {
    let settlementId: bigint;

    beforeEach(async () => {
      const flows = buildFlows(_fb);
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, false);
      const receipt = await tx.wait();
      const event = findEvent(receipt, "SettlementCreated");
      settlementId = event.args.settlementId;
    });

    it("[Case 1] Should succeed for a single settlement requiring ETH deposit", async () => {
      // Bob is from one flow where he needs to deposit ETH
      // from Bob -> Charlie is ETH
      const settleIds = [settlementId];
      const totalEthRequired = TOKEN_AMOUNT_SMALL_18_DECIMALS; // from Bob -> Charlie

      const tx = await _dvp
        .connect(_bob.wallet)
        .approveSettlements(settleIds, { value: totalEthRequired });
      const receipt = await tx.wait();

      const approvedEvent = findEvent(receipt, "SettlementApproved");
      expect(approvedEvent).not.to.be.undefined;
      expect(approvedEvent.args.settlementId).to.eql(settlementId);
      expect(approvedEvent.args.party).to.equal(_bob.address);

      const ethReceivedEvent = findEvent(receipt, "ETHReceived");
      expect(ethReceivedEvent).not.to.be.undefined;
      expect(ethReceivedEvent.args.party).to.equal(_bob.address);
      expect(ethReceivedEvent.args.amount).to.equal(totalEthRequired);

      // Check approval
      expect(await _dvp.isSettlementApproved(settlementId)).to.be.false; // not all parties approved yet

      // Cant check approval of a non-existent settlement
      await expect(
        _dvp.isSettlementApproved(NOT_A_SETTLEMENT_ID)
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.SettlementDoesNotExist
      );

      // Check deposit recorded
      const { etherDeposited } = await _dvp.getSettlementPartyStatus(
        settlementId,
        _bob.address
      );
      expect(etherDeposited).to.equal(totalEthRequired);
    });

    it("[Case 2] Should revert if settlement already executed", async () => {
      // Approve all parties so we can execute first
      await _dvp.connect(_alice.wallet).approveSettlements([settlementId]);
      await _dvp.connect(_bob.wallet).approveSettlements([settlementId], {
        value: TOKEN_AMOUNT_SMALL_18_DECIMALS,
      });
      await _dvp.connect(_charlie.wallet).approveSettlements([settlementId]);

      await _usdcToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_6_DECIMALS);
      await _daiToken
        .connect(_charlie.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_18_DECIMALS);

      await _dvp.connect(_alice.wallet).executeSettlement(settlementId);

      await expect(
        _dvp.connect(_alice.wallet).approveSettlements([settlementId])
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.SettlementAlreadyExecuted
      );
    });

    it("[Case 3] Should revert if cutoff date passed", async () => {
      // Move time forward beyond cutoff
      await moveInTime(_timestamps.nowPlus8Days);

      await expect(
        _dvp.connect(_alice.wallet).approveSettlements([settlementId])
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.CutoffDatePassed
      );
    });

    it("[Case 4] Should revert if approval already granted by the same party", async () => {
      await _dvp.connect(_alice.wallet).approveSettlements([settlementId]);
      await expect(
        _dvp.connect(_alice.wallet).approveSettlements([settlementId])
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.ApprovalAlreadyGranted
      );
    });

    it("[Case 5] Should revert if caller not involved in the settlement", async () => {
      // Dave is not part of the settlement
      await expect(
        _dvp.connect(_dave.wallet).approveSettlements([settlementId])
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.CallerNotInvolved
      );
    });

    it("[Case 6] Should revert if incorrect ETH amount sent", async () => {
      // Bob needs a certain ETH amount
      const requiredEth = TOKEN_AMOUNT_SMALL_18_DECIMALS;
      // send less than required
      await expect(
        _dvp
          .connect(_bob.wallet)
          .approveSettlements([settlementId], { value: requiredEth - 1n })
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.IncorrectETHAmount
      );

      // send more than required
      await expect(
        _dvp
          .connect(_bob.wallet)
          .approveSettlements([settlementId], { value: requiredEth + 1n })
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.IncorrectETHAmount
      );
    });

    it("[Case 7] Should succeed approving multiple settlements at once", async () => {
      // Create a second settlement with bob as a participant
      const flows2 = [
        {
          from: _bob.address,
          to: _alice.address,
          token: _usdt,
          isNFT: false,
          amountOrId: TOKEN_AMOUNT_SMALL_6_DECIMALS,
        },
      ];
      const cutoff2 = _timestamps.nowPlusDays(5);
      const tx2 = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows2, SETTLEMENT_REF, cutoff2, false);
      const receipt2 = await tx2.wait();
      const settlementId2 = findEvent(receipt2, "SettlementCreated").args
        .settlementId;

      // For settlementId2 no ETH is required from Bob
      await _dvp
        .connect(_bob.wallet)
        .approveSettlements([settlementId, settlementId2], {
          value: TOKEN_AMOUNT_SMALL_18_DECIMALS,
        });

      // Check approvals
      const { etherDeposited: deposit1 } = await _dvp.getSettlementPartyStatus(
        settlementId,
        _bob.address
      );
      expect(deposit1).to.equal(TOKEN_AMOUNT_SMALL_18_DECIMALS);

      const { etherDeposited: deposit2 } = await _dvp.getSettlementPartyStatus(
        settlementId2,
        _bob.address
      );
      expect(deposit2).to.equal(0n);
    });

    it("[Case 8] Should revert if settlement does not exist", async () => {
      await expect(
        _dvp.connect(_alice.wallet).approveSettlements([NOT_A_SETTLEMENT_ID])
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.SettlementDoesNotExist
      );
    });

    it("[Case 9] Should succeed for a single settlement with auto settlement", async () => {
      // Create settlement with auto settlement
      const flows = [
        {
          from: _alice.address,
          to: _bob.address,
          token: _usdc,
          isNFT: false,
          amountOrId: TOKEN_AMOUNT_SMALL_6_DECIMALS,
        },
      ];
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, true);
      const receipt = await tx.wait();
      const createSettlementEvent = findEvent(receipt, "SettlementCreated");
      expect(createSettlementEvent).not.to.be.undefined;
      const { settlementId } = createSettlementEvent.args;

      const { isAutoSettled } = await _dvp.getSettlement(settlementId);
      expect(isAutoSettled).to.be.true;

      // If Alice now approves, since she's the only approver, the settlement should auto-execute
      await _usdcToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_6_DECIMALS);
      const tx2 = await _dvp
        .connect(_alice.wallet)
        .approveSettlements([settlementId]);
      const receipt2 = await tx2.wait();
      // So should see settlement approved
      const approvedEvent = findEvent(receipt2, "SettlementApproved");
      expect(approvedEvent).not.to.be.undefined;
      expect(approvedEvent.args.settlementId).to.eql(settlementId);
      expect(approvedEvent.args.party).to.equal(_alice.address);
      expect(await _dvp.isSettlementApproved(settlementId)).to.be.true;
      // and executed
      const executedEvent = findEvent(receipt2, "SettlementExecuted");
      expect(executedEvent).not.to.be.undefined;
      expect(executedEvent.args.settlementId).to.equal(settlementId);
      expect(executedEvent.args.executor).to.equal(_alice.address);
      const { isSettled } = await _dvp.getSettlement(settlementId);
      expect(isSettled).to.be.true;
    });

    it("[Case 10] Should succeed for multiple settlements mixing regular and auto settlement", async () => {
      // Create settlement with regular approval
      const flowsRegular = [
        {
          from: _alice.address,
          to: _bob.address,
          token: _usdc,
          isNFT: false,
          amountOrId: TOKEN_AMOUNT_SMALL_6_DECIMALS,
        },
      ];
      const cutoff = _timestamps.nowPlusDays(7);
      const txRegular = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flowsRegular, SETTLEMENT_REF, cutoff, false);
      const receiptRegular = await txRegular.wait();
      const createSettlementEventRegular = findEvent(
        receiptRegular,
        "SettlementCreated"
      );
      expect(createSettlementEventRegular).not.to.be.undefined;
      const { settlementId: settlementIdRegular } =
        createSettlementEventRegular.args;
      const { isAutoSettled: isAutoSettledRegular } = await _dvp.getSettlement(
        settlementIdRegular
      );
      expect(isAutoSettledRegular).to.be.false;

      // Create settlement with auto settlement
      const flowsAuto = [
        {
          from: _alice.address,
          to: _bob.address,
          token: _usdc,
          isNFT: false,
          amountOrId: TOKEN_AMOUNT_SMALL_6_DECIMALS,
        },
      ];
      const txAuto = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flowsAuto, SETTLEMENT_REF, cutoff, true);
      const receiptAuto = await txAuto.wait();
      const createSettlementEventAuto = findEvent(
        receiptAuto,
        "SettlementCreated"
      );
      expect(createSettlementEventAuto).not.to.be.undefined;
      const { settlementId: settlementIdAuto } = createSettlementEventAuto.args;
      const { isAutoSettled: isAutoSettledAuto } = await _dvp.getSettlement(
        settlementIdAuto
      );
      expect(isAutoSettledAuto).to.be.true;

      // Alice will approve both settlements, but only the auto-settlement should be executed
      await _usdcToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_6_DECIMALS * 2n);
      const txApprove = await _dvp
        .connect(_alice.wallet)
        .approveSettlements([settlementIdRegular, settlementIdAuto]);
      const receiptApprove = await txApprove.wait();
      const executedEvent = findEvent(receiptApprove, "SettlementExecuted");
      expect(executedEvent).not.to.be.undefined;
      expect(executedEvent.args.settlementId).to.equal(settlementIdAuto);
      expect(executedEvent.args.executor).to.equal(_alice.address);
      const { isSettled: isSettledRegular } = await _dvp.getSettlement(
        settlementIdRegular
      );
      expect(isSettledRegular).to.be.false;
      const { isSettled: isSettledAuto } = await _dvp.getSettlement(
        settlementIdAuto
      );
      expect(isSettledAuto).to.be.true;
    });

    it("[Case 11] Should succeed for approval with NFT", async () => {
      // Create settlement with NFT
      const flows = buildFlowsNftSimple(_fb);
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, false);
      const receipt = await tx.wait();
      const createSettlementEvent = findEvent(receipt, "SettlementCreated");
      expect(createSettlementEvent).not.to.be.undefined;
      const { settlementId } = createSettlementEvent.args;

      // Alice approves that DVP contract can spend her cat, Daisy
      await _nftCatToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, NFT_CAT_DAISY);
      const txApprove = await _dvp
        .connect(_alice.wallet)
        .approveSettlements([settlementId]);
      const receiptApprove = await txApprove.wait();
      const approvedEvent = findEvent(receiptApprove, "SettlementApproved");
      expect(approvedEvent).not.to.be.undefined;
      expect(approvedEvent.args.settlementId).to.eql(settlementId);
      expect(approvedEvent.args.party).to.equal(_alice.address);
    });

    it("[Case 12] Should succeed for a single settlement with auto settlement but execution reverts with safeTransferFrom default message", async () => {
      // Create settlement with auto settlement
      const flows = [
        {
          from: _alice.address,
          to: _bob.address,
          token: _revert, // token that reverts when transfer is called
          isNFT: false,
          amountOrId: TOKEN_AMOUNT_FOR_REVERT_DEFAULT_MESSAGE,
        },
      ];
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, true);
      const receipt = await tx.wait();
      const createSettlementEvent = findEvent(receipt, "SettlementCreated");
      expect(createSettlementEvent).not.to.be.undefined;
      const { settlementId } = createSettlementEvent.args;

      // If Alice now approves, since she's the only approver, the settlement should auto-execute
      await _revertToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_6_DECIMALS);
      const tx2 = await _dvp
        .connect(_alice.wallet)
        .approveSettlements([settlementId]);
      const receipt2 = await tx2.wait();
      // So should see settlement approved
      const approvedEvent = findEvent(receipt2, "SettlementApproved");
      expect(approvedEvent).not.to.be.undefined;
      expect(approvedEvent.args.settlementId).to.eql(settlementId);
      expect(approvedEvent.args.party).to.equal(_alice.address);
      expect(await _dvp.isSettlementApproved(settlementId)).to.be.true;

      // but not executed
      const executionFailedEvent = findEvent(
        receipt2,
        "SettlementAutoExecutionFailedOther"
      );
      expect(executionFailedEvent).not.to.be.undefined;
      expect(executionFailedEvent.args.settlementId).to.equal(settlementId);
      expect(executionFailedEvent.args.executor).to.equal(_alice.address);
      expect(executionFailedEvent.args.lowLevelData).to.equal("0x");
      const { isSettled } = await _dvp.getSettlement(settlementId);
      expect(isSettled).to.be.false;
    });

    it("[Case 13] Should succeed for a single settlement with auto settlement but execution reverts with reason string", async () => {
      // Create settlement with auto settlement
      const flows = [
        {
          from: _alice.address,
          to: _bob.address,
          token: _revert, // token that reverts when transfer is called
          isNFT: false,
          amountOrId: TOKEN_AMOUNT_FOR_REVERT_STRING,
        },
      ];
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, true);
      const receipt = await tx.wait();
      const createSettlementEvent = findEvent(receipt, "SettlementCreated");
      expect(createSettlementEvent).not.to.be.undefined;
      const { settlementId } = createSettlementEvent.args;

      // If Alice now approves, since she's the only approver, the settlement should auto-execute
      await _revertToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_6_DECIMALS);
      const tx2 = await _dvp
        .connect(_alice.wallet)
        .approveSettlements([settlementId]);
      const receipt2 = await tx2.wait();
      // So should see settlement approved
      const approvedEvent = findEvent(receipt2, "SettlementApproved");
      expect(approvedEvent).not.to.be.undefined;
      expect(approvedEvent.args.settlementId).to.eql(settlementId);
      expect(approvedEvent.args.party).to.equal(_alice.address);
      expect(await _dvp.isSettlementApproved(settlementId)).to.be.true;

      // but not executed
      const executionFailedEvent = findEvent(
        receipt2,
        "SettlementAutoExecutionFailedReason"
      );
      expect(executionFailedEvent).not.to.be.undefined;
      expect(executionFailedEvent.args.settlementId).to.equal(settlementId);
      expect(executionFailedEvent.args.executor).to.equal(_alice.address);
      expect(executionFailedEvent.args.reason).to.equal(revertWithReasonString);
      const { isSettled } = await _dvp.getSettlement(settlementId);
      expect(isSettled).to.be.false;
    });

    it("[Case 14] Should succeed for a single settlement with auto settlement but execution reverts with panic", async () => {
      // Create settlement with auto settlement
      const flows = [
        {
          from: _alice.address,
          to: _bob.address,
          token: _revert, // token that reverts when transfer is called
          isNFT: false,
          amountOrId: TOKEN_AMOUNT_FOR_REVERT_PANIC,
        },
      ];
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, true);
      const receipt = await tx.wait();
      const createSettlementEvent = findEvent(receipt, "SettlementCreated");
      expect(createSettlementEvent).not.to.be.undefined;
      const { settlementId } = createSettlementEvent.args;

      // If Alice now approves, since she's the only approver, the settlement should auto-execute
      await _revertToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_6_DECIMALS);
      const tx2 = await _dvp
        .connect(_alice.wallet)
        .approveSettlements([settlementId]);
      const receipt2 = await tx2.wait();
      // So should see settlement approved
      const approvedEvent = findEvent(receipt2, "SettlementApproved");
      expect(approvedEvent).not.to.be.undefined;
      expect(approvedEvent.args.settlementId).to.eql(settlementId);
      expect(approvedEvent.args.party).to.equal(_alice.address);
      expect(await _dvp.isSettlementApproved(settlementId)).to.be.true;

      // but not executed
      const executionFailedEvent = findEvent(
        receipt2,
        "SettlementAutoExecutionFailedPanic"
      );
      expect(executionFailedEvent).not.to.be.undefined;
      expect(executionFailedEvent.args.settlementId).to.equal(settlementId);
      expect(executionFailedEvent.args.executor).to.equal(_alice.address);
      expect(executionFailedEvent.args.errorCode).to.equal(18); // Panic code 18 means div 0
      const { isSettled } = await _dvp.getSettlement(settlementId);
      expect(isSettled).to.be.false;
    });

    it("[Case 15] Should succeed for a single settlement with auto settlement but execution reverts with custom error", async () => {
      // Create settlement with auto settlement
      const flows = [
        {
          from: _alice.address,
          to: _bob.address,
          token: _revert, // token that reverts when transfer is called
          isNFT: false,
          amountOrId: TOKEN_AMOUNT_FOR_REVERT_CUSTOM_ERROR,
        },
      ];
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, true);
      const receipt = await tx.wait();
      const createSettlementEvent = findEvent(receipt, "SettlementCreated");
      expect(createSettlementEvent).not.to.be.undefined;
      const { settlementId } = createSettlementEvent.args;

      // If Alice now approves, since she's the only approver, the settlement should auto-execute
      await _revertToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_6_DECIMALS);
      const tx2 = await _dvp
        .connect(_alice.wallet)
        .approveSettlements([settlementId]);
      const receipt2 = await tx2.wait();
      // So should see settlement approved
      const approvedEvent = findEvent(receipt2, "SettlementApproved");
      expect(approvedEvent).not.to.be.undefined;
      expect(approvedEvent.args.settlementId).to.eql(settlementId);
      expect(approvedEvent.args.party).to.equal(_alice.address);
      expect(await _dvp.isSettlementApproved(settlementId)).to.be.true;

      // but not executed
      const executionFailedEvent = findEvent(
        receipt2,
        "SettlementAutoExecutionFailedOther"
      );
      expect(executionFailedEvent).not.to.be.undefined;
      expect(executionFailedEvent.args.settlementId).to.equal(settlementId);
      expect(executionFailedEvent.args.executor).to.equal(_alice.address);
      // low level data in this case is the error selector for "ThisIsACustomError()" which is 0x0a59c53c
      expect(executionFailedEvent.args.lowLevelData).to.equal("0x0a59c53c");
      const { isSettled } = await _dvp.getSettlement(settlementId);
      expect(isSettled).to.be.false;
    });

    it("[Case 16] Should succeed for multiple settlements all with auto settlement but some execution reverts", async () => {
      // Create settlement with auto settlement that will execute ok
      const flowsExeOk = [
        {
          from: _alice.address,
          to: _bob.address,
          token: _usdc,
          isNFT: false,
          amountOrId: TOKEN_AMOUNT_SMALL_6_DECIMALS,
        },
      ];
      const cutoff = _timestamps.nowPlusDays(7);
      let tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flowsExeOk, SETTLEMENT_REF, cutoff, true);
      let receipt = await tx.wait();
      let createSettlementEvent = findEvent(receipt, "SettlementCreated");
      expect(createSettlementEvent).not.to.be.undefined;
      const { settlementId: settlementIdExeOk } = createSettlementEvent.args;

      // Create settlement with auto settlement that will revert during execution
      const flowsExeRevert = [
        {
          from: _alice.address,
          to: _bob.address,
          token: _revert,
          isNFT: false,
          amountOrId: TOKEN_AMOUNT_FOR_REVERT_DEFAULT_MESSAGE,
        },
      ];
      tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flowsExeRevert, SETTLEMENT_REF, cutoff, true);
      receipt = await tx.wait();
      createSettlementEvent = findEvent(receipt, "SettlementCreated");
      expect(createSettlementEvent).not.to.be.undefined;
      const { settlementId: settlementIdExeRevert } =
        createSettlementEvent.args;

      // Alice will approve both settlements, but only the auto-settlement should be executed
      await _usdcToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_6_DECIMALS * 2n);
      await _revertToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_6_DECIMALS * 2n);
      const txApprove = await _dvp
        .connect(_alice.wallet)
        .approveSettlements([settlementIdExeOk, settlementIdExeRevert]);
      const receiptApprove = await txApprove.wait();

      // one settlement approved and executes ok
      const executedEvent = findEvent(receiptApprove, "SettlementExecuted");
      expect(executedEvent).not.to.be.undefined;
      expect(executedEvent.args.settlementId).to.equal(settlementIdExeOk);
      expect(executedEvent.args.executor).to.equal(_alice.address);
      expect(await _dvp.isSettlementApproved(settlementIdExeOk)).to.be.true;
      const { isSettled: isSettledExeOk } = await _dvp.getSettlement(
        settlementIdExeOk
      );
      expect(isSettledExeOk).to.be.true;

      // one settlement approved but doesnt execute
      const executionFailedEvent = findEvent(
        receiptApprove,
        "SettlementAutoExecutionFailedOther"
      );
      expect(executionFailedEvent).not.to.be.undefined;
      expect(executionFailedEvent.args.settlementId).to.equal(
        settlementIdExeRevert
      );
      expect(executionFailedEvent.args.executor).to.equal(_alice.address);
      expect(executionFailedEvent.args.lowLevelData).to.equal("0x");
      expect(await _dvp.isSettlementApproved(settlementIdExeOk)).to.be.true;
      const { isSettled: isSettledExeRevert } = await _dvp.getSettlement(
        settlementIdExeRevert
      );
      expect(isSettledExeRevert).to.be.false;
    });
  });

  describe.only("[Function] executeSettlement", async () => {
    let settlementId: bigint;
    let settlementMixedId: bigint;
    beforeEach(async () => {
      //------------------------------------------------------------
      // Settlement with tokens
      //------------------------------------------------------------
      const flows = buildFlows(_fb);
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, false);
      const receipt = await tx.wait();
      settlementId = findEvent(receipt, "SettlementCreated").args.settlementId;

      // Approvals
      await _dvp.connect(_alice.wallet).approveSettlements([settlementId]);
      await _dvp.connect(_bob.wallet).approveSettlements([settlementId], {
        value: TOKEN_AMOUNT_SMALL_18_DECIMALS,
      });
      await _dvp.connect(_charlie.wallet).approveSettlements([settlementId]);

      // Approve tokens
      await _usdcToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_6_DECIMALS);
      await _daiToken
        .connect(_charlie.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_18_DECIMALS);

      //------------------------------------------------------------
      // Settlement with mixed tokens and NFTs
      //------------------------------------------------------------
      const flowsMixed = buildFlowsMixed(_fb);
      const txMixed = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flowsMixed, SETTLEMENT_REF, cutoff, false);
      const receiptMixed = await txMixed.wait();
      settlementMixedId = findEvent(receiptMixed, "SettlementCreated").args
        .settlementId;

      // Approvals
      await _dvp.connect(_alice.wallet).approveSettlements([settlementMixedId]);
      await _dvp.connect(_bob.wallet).approveSettlements([settlementMixedId], {
        value: TOKEN_AMOUNT_SMALL_18_DECIMALS,
      });
      await _dvp
        .connect(_charlie.wallet)
        .approveSettlements([settlementMixedId]);

      // Approve that DVP contract can spend tokens & NFTs
      await _usdcToken
        .connect(_charlie.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_6_DECIMALS);
      await _nftCatToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, NFT_CAT_DAISY);
    });

    it("[Case 1] Should succeed if all approved and conditions met", async () => {
      // The settlement created in test setup is:
      //   Alice   -> Bob     USDC
      //   Bob     -> Charlie ETH
      //   Charlie -> Alice   DAI

      // Capture balances before
      const oldAliceDaiBalance = await _daiToken.balanceOf(_alice.address);
      const oldCharlieEthBalance = await ethers.provider.getBalance(
        _charlie.address
      );

      // Execute settlement
      const tx = await _dvp
        .connect(_alice.wallet)
        .executeSettlement(settlementId);
      const receipt = await tx.wait();
      const executedEvent = findEvent(receipt, "SettlementExecuted");
      expect(executedEvent).not.to.be.undefined;
      expect(executedEvent.args.settlementId).to.equal(settlementId);
      expect(executedEvent.args.executor).to.equal(_alice.address);

      // Check ETH transfer (Bob -> Charlie)
      // Charlie should receive the exact ETH amount (TOKEN_AMOUNT_SMALL_18_DECIMALS)
      const newCharlieEthBalance = await ethers.provider.getBalance(
        _charlie.address
      );
      expect(newCharlieEthBalance - oldCharlieEthBalance).to.equal(
        TOKEN_AMOUNT_SMALL_18_DECIMALS
      );

      // Bob's deposit should now be zero since it has been transferred to Charlie
      const { etherDeposited: bobDepositAfter } =
        await _dvp.getSettlementPartyStatus(settlementId, _bob.address);
      expect(bobDepositAfter).to.equal(0n);

      // Check token transfers:
      // Alice -> Bob USDC
      const bobUsdcBalance = await _usdcToken.balanceOf(_bob.address);
      expect(bobUsdcBalance).to.be.gte(TOKEN_AMOUNT_SMALL_6_DECIMALS);

      // Charlie -> Alice DAI
      const aliceDaiBalanceAfter = await _daiToken.balanceOf(_alice.address);
      expect(aliceDaiBalanceAfter - oldAliceDaiBalance).to.equal(
        TOKEN_AMOUNT_SMALL_18_DECIMALS
      );

      // Settlement marked as settled
      const { isSettled } = await _dvp.getSettlement(settlementId);
      expect(isSettled).to.be.true;
    });

    it("[Case 2] Should succeed for mixed flows with NFTs if all approved and conditions met", async () => {
      // The settlementMixed created in test setup is:
      //   Alice   -> Bob     Her cat Daisy
      //   Bob     -> Charlie ETH
      //   Charlie -> Alice   USDC

      // Capture balances before
      const aliceUsdcBalanceBefore = await _usdcToken.balanceOf(_alice.address);
      const bobIsCatOwnerBefore =
        _bob.address == (await _nftCatToken.ownerOf(NFT_CAT_DAISY));
      const charlieEthBalanceBefore = await ethers.provider.getBalance(
        _charlie.address
      );
      expect(bobIsCatOwnerBefore).to.be.false;

      // Execute settlement
      const tx = await _dvp
        .connect(_alice.wallet)
        .executeSettlement(settlementMixedId);
      const receipt = await tx.wait();
      const executedEvent = findEvent(receipt, "SettlementExecuted");
      expect(executedEvent).not.to.be.undefined;
      expect(executedEvent.args.settlementId).to.equal(settlementMixedId);
      expect(executedEvent.args.executor).to.equal(_alice.address);

      // Check Daisy the cat (Alice -> Bob), Bob should now have the cat
      const bobIsCatOwnerAfter =
        _bob.address == (await _nftCatToken.ownerOf(NFT_CAT_DAISY));
      expect(bobIsCatOwnerAfter).to.be.true;

      // Check ETH transfer (Bob -> Charlie)
      const charlieEthBalanceAfter = await ethers.provider.getBalance(
        _charlie.address
      );
      expect(charlieEthBalanceAfter - charlieEthBalanceBefore).to.equal(
        TOKEN_AMOUNT_SMALL_18_DECIMALS
      );

      // Check token transfer (Charlie -> Alice) USDC
      const aliceUsdcBalanceAfter = await _usdcToken.balanceOf(_alice.address);
      expect(aliceUsdcBalanceAfter - aliceUsdcBalanceBefore).to.equal(
        TOKEN_AMOUNT_SMALL_6_DECIMALS
      );

      // Settlement marked as settled
      const { isSettled } = await _dvp.getSettlement(settlementMixedId);
      expect(isSettled).to.be.true;
    });

    it("[Case 3] Should succeed for with NFT approved with setApprovalForAll", async () => {
      // The settlementMixed created in test setup is:
      //   Alice   -> Bob     Her cat Daisy
      //   Bob     -> Charlie ETH
      //   Charlie -> Alice   USDC

      // Remove Alice's single approval for Daisy and replace it with the "approve all my NFTs" equivalent
      await _nftCatToken
        .connect(_alice.wallet)
        .approve(ethers.ZeroAddress, NFT_CAT_DAISY);
      await _nftCatToken
        .connect(_alice.wallet)
        .setApprovalForAll(_dvpAddress, true);
      const bobIsCatOwnerBefore =
        _bob.address == (await _nftCatToken.ownerOf(NFT_CAT_DAISY));
      expect(bobIsCatOwnerBefore).to.be.false;

      // Execute settlement
      const tx = await _dvp
        .connect(_alice.wallet)
        .executeSettlement(settlementMixedId);
      const receipt = await tx.wait();
      const executedEvent = findEvent(receipt, "SettlementExecuted");
      expect(executedEvent).not.to.be.undefined;
      expect(executedEvent.args.settlementId).to.equal(settlementMixedId);
      expect(executedEvent.args.executor).to.equal(_alice.address);

      // Check Daisy the cat (Alice -> Bob), Bob should now have the cat
      const bobIsCatOwnerAfter =
        _bob.address == (await _nftCatToken.ownerOf(NFT_CAT_DAISY));
      expect(bobIsCatOwnerAfter).to.be.true;

      // Settlement marked as settled
      const { isSettled } = await _dvp.getSettlement(settlementMixedId);
      expect(isSettled).to.be.true;
    });

    it("[Case 4] Should revert if cutoff date passed", async () => {
      // Move time forward beyond cutoff
      await moveInTime(_timestamps.nowPlus8Days);

      await expect(
        _dvp.connect(_alice.wallet).executeSettlement(settlementId)
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.CutoffDatePassed
      );
    });

    it("[Case 5] Should revert if settlement already executed", async () => {
      await _dvp.connect(_alice.wallet).executeSettlement(settlementId);
      await expect(
        _dvp.connect(_alice.wallet).executeSettlement(settlementId)
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.SettlementAlreadyExecuted
      );
    });

    it("[Case 6] Should revert if not all approved", async () => {
      // Create a new settlement and do not approve by all parties
      const flows2 = [
        {
          from: _alice.address,
          to: _bob.address,
          token: _usdc,
          isNFT: false,
          amountOrId: TOKEN_AMOUNT_SMALL_6_DECIMALS,
        },
        {
          from: _bob.address,
          to: _alice.address,
          token: _usdc,
          isNFT: false,
          amountOrId: TOKEN_AMOUNT_SMALL_6_DECIMALS,
        },
      ];
      const cutoff2 = _timestamps.nowPlusDays(2);
      const tx2 = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows2, SETTLEMENT_REF, cutoff2, false);
      const receipt2 = await tx2.wait();
      const settlementId2 = findEvent(receipt2, "SettlementCreated").args
        .settlementId;
      // Only Alice approves
      await _dvp.connect(_alice.wallet).approveSettlements([settlementId2]);
      await _usdcToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_6_DECIMALS);

      await expect(
        _dvp.connect(_alice.wallet).executeSettlement(settlementId2)
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.SettlementNotApproved
      );
    });

    it("[Case 7] Should revert if insufficient ETH deposited", async () => {
      // Create a new settlement requiring ETH from Bob, but Bob won't approve
      const flows2 = [
        {
          from: _bob.address,
          to: _alice.address,
          token: _eth,
          isNFT: false,
          amountOrId: TOKEN_AMOUNT_SMALL_18_DECIMALS,
        },
      ];
      const cutoff2 = _timestamps.nowPlusDays(2);
      const tx2 = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows2, SETTLEMENT_REF, cutoff2, false);
      const receipt2 = await tx2.wait();
      const settlementId2 = findEvent(receipt2, "SettlementCreated").args
        .settlementId;

      // Only Bob needs to approve but he doesn't send any ETH
      await expect(
        _dvp.connect(_bob.wallet).approveSettlements([settlementId2])
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.IncorrectETHAmount
      );

      // Approve with ETH, but still too little
      await expect(
        _dvp.connect(_bob.wallet).approveSettlements([settlementId2], {
          value: TOKEN_AMOUNT_SMALL_18_DECIMALS - 1n,
        })
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.IncorrectETHAmount
      );

      // Approve with correct ETH
      await expect(
        _dvp.connect(_bob.wallet).approveSettlements([settlementId2], {
          value: TOKEN_AMOUNT_SMALL_18_DECIMALS,
        })
      ).to.not.be.reverted;
    });

    it("[Case 8] Should revert if insufficient allowance", async () => {
      // Remove allowance for Alice on the original settlement
      await _usdcToken.connect(_alice.wallet).approve(_dvpAddress, 0);

      await expect(
        _dvp.connect(_alice.wallet).executeSettlement(settlementId)
      ).to.be.revertedWith(erc20TransferExceedsAllowance);
    });

    it("[Case 9] Should revert if insufficient balance", async () => {
      // Drain Alice's USDC balance
      const aliceUsdcBalance = await _usdcToken.balanceOf(_alice.address);
      await _usdcToken
        .connect(_alice.wallet)
        .transfer(_deployer.address, aliceUsdcBalance);

      await expect(
        _dvp.connect(_alice.wallet).executeSettlement(settlementId)
      ).to.be.revertedWith(erc20TransferExceedsBalance);
    });

    it("[Case 10] Should revert on attempted re-entrancy by token", async () => {
      // Create settlement involving malicious token
      await _maliciousToken.connect(_alice.wallet).approve(_dvpAddress, 10n);
      const flows = [
        {
          from: _alice.address,
          to: _bob.address,
          token: _maliciousTokenAddress,
          isNFT: false,
          amountOrId: 1n,
        },
      ];
      const cutoff = _timestamps.nowPlusDays(7);
      const createTx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, false);
      const createReceipt = await createTx.wait();
      const settlementId = findEvent(createReceipt, "SettlementCreated").args
        .settlementId;

      // Alice approves settlement
      await _dvp.connect(_alice.wallet).approveSettlements([settlementId]);

      // Attempt to execute the settlement causes maliciousToken.transferFrom() to trigger re-entrancy
      _maliciousToken
        .connect(_alice.wallet)
        .setTargetSettlementId(settlementId);
      await expect(
        _dvp.connect(_alice.wallet).executeSettlement(settlementId)
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.ReentrancyGuardReentrantCall
      );
    });

    it("[Case 11] Should revert on attempted re-entrancy by ETH wallet", async () => {
      // Settlement with malicious actor as receiver during execution
      const flows = [
        {
          from: _alice.address,
          to: _maliciousActorAddress,
          token: _eth,
          isNFT: false,
          amountOrId: 1n,
        },
      ];
      const cutoff = _timestamps.nowPlusDays(7);
      const createTx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, false);
      const createReceipt = await createTx.wait();
      const settlementId = findEvent(createReceipt, "SettlementCreated").args
        .settlementId;

      // Alice approves settlement
      await _dvp
        .connect(_alice.wallet)
        .approveSettlements([settlementId], { value: 1n });

      // Attempt to execute the settlement causes _maliciousActor.receive() to trigger re-entrancy
      _maliciousActor
        .connect(_deployer.wallet)
        .setTargetSettlementId(settlementId);
      _maliciousActor
        .connect(_deployer.wallet)
        .setReentrancyMode(ReentrancyMode.ExecuteSettlement);
      await sleep(500); // intermittently, reentrancy does not revert
      // Notice anyone can process the settlement
      await expect(
        _dvp.connect(_alice.wallet).executeSettlement(settlementId)
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.ReentrancyGuardReentrantCall
      );
    });

    it("[Case 12] Should revert if settlement does not exist", async () => {
      await expect(
        _dvp.connect(_alice.wallet).executeSettlement(NOT_A_SETTLEMENT_ID)
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.SettlementDoesNotExist
      );
    });

    it("[Case 13] Should revert if NFT id allowance was not given", async () => {
      // Remove allowance for Alice's cat that was given to the DVP contract
      await _nftCatToken
        .connect(_alice.wallet)
        .approve(ethers.ZeroAddress, NFT_CAT_DAISY);

      await expect(
        _dvp.connect(_alice.wallet).executeSettlement(settlementMixedId)
      ).to.be.revertedWith(erc721TransferCallerNotOwnerNorApproved);
    });

    it("[Case 14] Should revert if user does not have the promised NFT id", async () => {
      // Alice gives her cat to Dave, so settlement cannot succeed
      await _nftCatToken
        .connect(_alice.wallet)
        ["safeTransferFrom(address,address,uint256)"](
          _alice.address,
          _dave.address,
          NFT_CAT_DAISY
        );
      await expect(
        _dvp.connect(_alice.wallet).executeSettlement(settlementMixedId)
      ).to.be.revertedWith(erc721TransferCallerNotOwnerNorApproved);
    });

    it("[Case 15] Should revert if NFT id does not exist", async () => {
      // An animal was hurt in the making of this test
      await _nftCatToken.connect(_alice.wallet).burn(NFT_CAT_DAISY);
      await expect(
        _dvp.connect(_alice.wallet).executeSettlement(settlementMixedId)
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.NoFlowsProvided
      );

      //(erc721OperatorQueryForNonexistentToken);
    });
  });

  describe("[Function] revokeApprovals", async () => {
    let settlementId: bigint;
    beforeEach(async () => {
      const flows = buildFlows(_fb);
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, false);
      const receipt = await tx.wait();
      settlementId = findEvent(receipt, "SettlementCreated").args.settlementId;

      await _dvp.connect(_alice.wallet).approveSettlements([settlementId]);
      await _dvp.connect(_bob.wallet).approveSettlements([settlementId], {
        value: TOKEN_AMOUNT_SMALL_18_DECIMALS,
      });
      await _dvp.connect(_charlie.wallet).approveSettlements([settlementId]);
    });

    it("[Case 1] Should succeed when returning ETH deposit", async () => {
      const bobBalanceBefore = await ethers.provider.getBalance(_bob.address);
      const { etherDeposited: bobDepositBefore } =
        await _dvp.getSettlementPartyStatus(settlementId, _bob.address);
      expect(bobDepositBefore).to.equal(TOKEN_AMOUNT_SMALL_18_DECIMALS);

      // Revoke approval
      const tx = await _dvp
        .connect(_bob.wallet)
        .revokeApprovals([settlementId]);
      const receipt = await tx.wait();
      expect(receipt).to.not.be.undefined;
      const revokeEvent = findEvent(receipt, "SettlementApprovalRevoked");
      expect(revokeEvent).not.to.be.undefined;
      expect(revokeEvent.args.settlementId).to.equal(settlementId);
      expect(revokeEvent.args.party).to.equal(_bob.address);

      const { etherDeposited: bobDepositAfter } =
        await _dvp.getSettlementPartyStatus(settlementId, _bob.address);
      expect(bobDepositAfter).to.equal(0n);

      // Bob got ETH back
      const bobBalanceAfter = await ethers.provider.getBalance(_bob.address);
      expect(bobBalanceAfter).to.be.gt(bobBalanceBefore);
    });

    it("[Case 2] Should succeed when no ETH deposit", async () => {
      // Create a second settlement that requires no ETH
      const flows2 = [
        {
          from: _alice.address,
          to: _bob.address,
          token: _usdc,
          isNFT: false,
          amountOrId: 1n,
        },
      ];
      const cutoff2 = _timestamps.nowPlusDays(7);
      const tx2 = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows2, SETTLEMENT_REF, cutoff2, false);
      const receipt2 = await tx2.wait();
      const settlementId2 = findEvent(receipt2, "SettlementCreated").args
        .settlementId;

      // Alice approves
      await _dvp.connect(_alice.wallet).approveSettlements([settlementId2]);

      // Revoke approval from Alice
      const { etherDeposited: aliceDepositBefore } =
        await _dvp.getSettlementPartyStatus(settlementId2, _alice.address);
      expect(aliceDepositBefore).to.equal(0n);
      const revokeTx = await _dvp
        .connect(_alice.wallet)
        .revokeApprovals([settlementId2]);
      const revokeReceipt = await revokeTx.wait();

      // Confirm settlement revoked
      const revokeEvent = findEvent(revokeReceipt, "SettlementApprovalRevoked");
      expect(revokeEvent).not.to.be.undefined;
      expect(revokeEvent.args.settlementId).to.equal(settlementId2);
      expect(revokeEvent.args.party).to.equal(_alice.address);

      // Confirm no ETH deposit updated
      const { etherDeposited: aliceDepositAfter } =
        await _dvp.getSettlementPartyStatus(settlementId2, _alice.address);
      expect(aliceDepositAfter).to.equal(0n);
    });

    it("[Case 3] Should revert if settlement already executed", async () => {
      await _usdcToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_6_DECIMALS);
      await _daiToken
        .connect(_charlie.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_18_DECIMALS);
      await _dvp.connect(_alice.wallet).executeSettlement(settlementId);

      await expect(
        _dvp.connect(_alice.wallet).revokeApprovals([settlementId])
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.SettlementAlreadyExecuted
      );
    });

    it("[Case 4] Should revert if approval not granted by caller", async () => {
      // Another new settlement not approved by Alice
      const flows2 = [
        {
          from: _charlie.address,
          to: _bob.address,
          token: _eth,
          isNFT: false,
          amountOrId: TOKEN_AMOUNT_SMALL_18_DECIMALS,
        },
      ];
      const cutoff2 = _timestamps.nowPlusDays(7);
      const tx2 = await _dvp
        .connect(_charlie.wallet)
        .createSettlement(flows2, SETTLEMENT_REF, cutoff2, false);
      const receipt2 = await tx2.wait();
      const settlementId2 = findEvent(receipt2, "SettlementCreated").args
        .settlementId;

      // Charlie did not approve yet
      await expect(
        _dvp.connect(_alice.wallet).revokeApprovals([settlementId2])
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.ApprovalNotGranted
      );
    });

    it("[Case 5] Should revert on attempted re-entrancy by ETH wallet", async () => {
      // Settlement with malicious actor as the sender
      const flows2 = [
        {
          from: _maliciousActorAddress,
          to: _alice.address,
          token: _eth,
          isNFT: false,
          amountOrId: 1n,
        },
      ];
      const cutoff2 = _timestamps.nowPlusDays(1);
      const createTx2 = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows2, SETTLEMENT_REF, cutoff2, false);
      const createReceipt2 = await createTx2.wait();
      const settlementId2 = findEvent(createReceipt2, "SettlementCreated").args
        .settlementId;

      // Malicious actor sets up target + re-entrancy mode = RevokeApproval
      await _maliciousActor
        .connect(_deployer.wallet)
        .setTargetSettlementId(settlementId2);
      await _maliciousActor
        .connect(_deployer.wallet)
        .setReentrancyMode(ReentrancyMode.RevokeApproval);

      // Approve settlement with 1 wei deposit from malicious actor
      await _maliciousActor
        .connect(_deployer.wallet)
        .approveSettlement({ value: 1n });

      // Attempt to revoke ETH approval ultimately causes _maliciousActor.receive() to trigger re-entrancy
      await expect(
        _maliciousActor.connect(_deployer.wallet).revokeApproval()
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.ReentrancyGuardReentrantCall
      );
    });

    it("[Case 6] Should revert if settlement does not exist", async () => {
      await expect(
        _dvp.connect(_alice.wallet).revokeApprovals([NOT_A_SETTLEMENT_ID])
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.SettlementDoesNotExist
      );
    });
  });

  describe("[Function] withdrawETH", async () => {
    let settlementId: bigint;
    beforeEach(async () => {
      const flows = buildFlows(_fb);
      const cutoff = _timestamps.nowPlusDays(1); // short cutoff
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, false);
      const receipt = await tx.wait();
      settlementId = findEvent(receipt, "SettlementCreated").args.settlementId;

      await _dvp.connect(_alice.wallet).approveSettlements([settlementId]);
      await _dvp.connect(_bob.wallet).approveSettlements([settlementId], {
        value: TOKEN_AMOUNT_SMALL_18_DECIMALS,
      });
      await _dvp.connect(_charlie.wallet).approveSettlements([settlementId]);
    });
    it("[Case 1] Should succeed with withdrawal of ETH deposit after cutoff", async () => {
      const bobBalanceBefore = await ethers.provider.getBalance(_bob.address);
      const { etherDeposited: bobDepositBefore } =
        await _dvp.getSettlementPartyStatus(settlementId, _bob.address);
      expect(bobDepositBefore).to.equal(TOKEN_AMOUNT_SMALL_18_DECIMALS);

      // Move time forward beyond cutoff
      await moveInTime(_timestamps.nowPlus8Days);

      // Withdraw ETH
      const tx = await _dvp.connect(_bob.wallet).withdrawETH(settlementId);
      const receipt = await tx.wait();
      const withdrawEvent = findEvent(receipt, "ETHWithdrawn");
      expect(withdrawEvent).not.to.be.undefined;
      expect(withdrawEvent.args.party).to.equal(_bob.address);
      expect(withdrawEvent.args.amount).to.equal(
        TOKEN_AMOUNT_SMALL_18_DECIMALS
      );

      const { etherDeposited: bobDepositAfter } =
        await _dvp.getSettlementPartyStatus(settlementId, _bob.address);
      expect(bobDepositAfter).to.equal(0n);

      // Bob got ETH back
      const bobBalanceAfter = await ethers.provider.getBalance(_bob.address);
      expect(bobBalanceAfter).to.be.gt(bobBalanceBefore);
    });

    it("[Case 2] Should revert if cutoff date not passed", async () => {
      await expect(
        _dvp.connect(_bob.wallet).withdrawETH(settlementId)
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.CutoffDatePassed
      );
    });

    it("[Case 3] Should revert if settlement executed", async () => {
      // Execute the settlement first
      await _usdcToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_6_DECIMALS);
      await _daiToken
        .connect(_charlie.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_18_DECIMALS);
      await _dvp.connect(_alice.wallet).executeSettlement(settlementId);

      // Move time forward
      await moveInTime(_timestamps.nowPlus8Days);

      await expect(
        _dvp.connect(_bob.wallet).withdrawETH(settlementId)
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.SettlementAlreadyExecuted
      );
    });

    it("[Case 4] Should revert if no ETH to withdraw", async () => {
      // Another settlement where Alice doesn't deposit ETH
      const flows2 = [
        {
          from: _alice.address,
          to: _bob.address,
          token: _usdc,
          isNFT: false,
          amountOrId: TOKEN_AMOUNT_SMALL_6_DECIMALS,
        },
      ];
      const cutoff2 = _timestamps.nowPlusDays(1);
      const tx2 = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows2, SETTLEMENT_REF, cutoff2, false);
      const receipt2 = await tx2.wait();
      const settlementId2 = findEvent(receipt2, "SettlementCreated").args
        .settlementId;
      await _dvp.connect(_alice.wallet).approveSettlements([settlementId2]);
      // No ETH deposit required from Alice

      // Move time forward
      await moveInTime(_timestamps.nowPlus8Days);

      await expect(
        _dvp.connect(_alice.wallet).withdrawETH(settlementId2)
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.NoETHToWithdraw
      );
    });

    it("[Case 5] Should revert on attempted re-entrancy by ETH wallet", async () => {
      // Settlement with malicious actor as sender, who will later call withdrawETH
      const flows = [
        {
          from: _maliciousActorAddress,
          to: _alice.address,
          token: _eth,
          isNFT: false,
          amountOrId: 1n,
        },
      ];
      const cutoff = _timestamps.nowPlus16Minutes;
      const createTx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, false);
      const createReceipt = await createTx.wait();
      const settlementId = findEvent(createReceipt, "SettlementCreated").args
        .settlementId;

      // Malicious actor approves settlement
      await _maliciousActor
        .connect(_deployer.wallet)
        .setTargetSettlementId(settlementId);
      await _maliciousActor
        .connect(_deployer.wallet)
        .setReentrancyMode(ReentrancyMode.WithdrawETH);
      await _maliciousActor
        .connect(_deployer.wallet)
        .approveSettlement({ value: 1n });

      // Settlement expires
      await moveInTime(_timestamps.nowPlus33Minutes);

      // Attempt to withdraw ETH ultimately causes _maliciousActor.receive() to trigger re-entrancy
      await expect(
        _maliciousActor.connect(_deployer.wallet).withdrawETH()
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.ReentrancyGuardReentrantCall
      );
    });

    it("[Case 6] Should revert if settlement does not exist", async () => {
      await expect(
        _dvp.connect(_bob.wallet).withdrawETH(NOT_A_SETTLEMENT_ID)
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.SettlementDoesNotExist
      );
    });
  });

  describe("[Function] getSettlementPartyStatus", () => {
    it("[Case 1] Should show correct statuses for parties throughout settlement lifecycle", async () => {
      const flows = buildFlowsComplex(_fb);
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, false);
      const receipt = await tx.wait();
      const settlementId = findEvent(receipt, "SettlementCreated").args
        .settlementId;

      //--------------------------------------------------------------------------------
      // Before approvals
      //--------------------------------------------------------------------------------
      // Alice: sends 100 base units of USDC, 1,000,000 WEI, and 2,000,000 base units of DAI.
      // So Approved=false, 1,000,000 WEI required, 0 deposited, USDC & DAI in tokenStatuses
      await getAndCheckPartyStatus(_dvp, settlementId, _alice.address, {
        // Expected results:
        approved: false,
        etherRequired: 1_000_000n,
        etherDeposited: 0n,
        tokenStatuses: [
          {
            tokenAddress: _usdc,
            isNFT: false,
            amountOrIdRequired: 100n,
            amountOrIdApprovedForDvp: 0n,
            amountOrIdHeldByParty: TOKEN_AMOUNT_LARGE_6_DECIMALS,
          },
          {
            tokenAddress: _dai,
            isNFT: false,
            amountOrIdRequired: 2_000_000n,
            amountOrIdApprovedForDvp: 0n,
            amountOrIdHeldByParty: TOKEN_AMOUNT_LARGE_18_DECIMALS,
          },
        ],
      });

      // Bob sends 1,500,000 WEI in total, so 1,500,000 WEI required, no token
      await getAndCheckPartyStatus(_dvp, settlementId, _bob.address, {
        // Expected results:
        approved: false,
        etherRequired: 1_500_000n,
        etherDeposited: 0n,
        tokenStatuses: [],
      });

      // Charlie sends 2,000,000 base units of DAI, no WEI
      await getAndCheckPartyStatus(_dvp, settlementId, _charlie.address, {
        // Expected results:
        approved: false,
        etherRequired: 0n,
        etherDeposited: 0n,
        tokenStatuses: [
          {
            tokenAddress: _dai,
            isNFT: false,
            amountOrIdRequired: 2_000_000n,
            amountOrIdApprovedForDvp: 0n,
            amountOrIdHeldByParty: TOKEN_AMOUNT_LARGE_18_DECIMALS,
          },
        ],
      });

      //--------------------------------------------------------------------------------
      // Approvals
      //--------------------------------------------------------------------------------
      await _dvp
        .connect(_alice.wallet)
        .approveSettlements([settlementId], { value: 1_000_000n });
      await _dvp
        .connect(_bob.wallet)
        .approveSettlements([settlementId], { value: 1_500_000n });
      await _dvp.connect(_charlie.wallet).approveSettlements([settlementId]);
      await _usdcToken.connect(_alice.wallet).approve(_dvpAddress, 100n);
      await _daiToken.connect(_alice.wallet).approve(_dvpAddress, 2_000_000n);
      await _daiToken.connect(_charlie.wallet).approve(_dvpAddress, 2_000_000n);

      //--------------------------------------------------------------------------------
      // After approvals
      //--------------------------------------------------------------------------------
      // Alice
      await getAndCheckPartyStatus(_dvp, settlementId, _alice.address, {
        // Expected results:
        approved: true,
        etherRequired: 1_000_000n,
        etherDeposited: 1_000_000n,
        tokenStatuses: [
          {
            tokenAddress: _usdc,
            isNFT: false,
            amountOrIdRequired: 100n,
            amountOrIdApprovedForDvp: 100n,
            amountOrIdHeldByParty: TOKEN_AMOUNT_LARGE_6_DECIMALS,
          },
          {
            tokenAddress: _dai,
            isNFT: false,
            amountOrIdRequired: 2_000_000n,
            amountOrIdApprovedForDvp: 2_000_000n,
            amountOrIdHeldByParty: TOKEN_AMOUNT_LARGE_18_DECIMALS,
          },
        ],
      });

      // Bob
      await getAndCheckPartyStatus(_dvp, settlementId, _bob.address, {
        // Expected results:
        approved: true,
        etherRequired: 1_500_000n,
        etherDeposited: 1_500_000n,
        tokenStatuses: [],
      });

      // Charlie
      await getAndCheckPartyStatus(_dvp, settlementId, _charlie.address, {
        // Expected results:
        approved: true,
        etherRequired: 0n,
        etherDeposited: 0n,
        tokenStatuses: [
          {
            tokenAddress: _dai,
            isNFT: false,
            amountOrIdRequired: 2_000_000n,
            amountOrIdApprovedForDvp: 2_000_000n,
            amountOrIdHeldByParty: TOKEN_AMOUNT_LARGE_18_DECIMALS,
          },
        ],
      });

      //--------------------------------------------------------------------------------
      // Execution
      //--------------------------------------------------------------------------------
      await _dvp.connect(_alice.wallet).executeSettlement(settlementId);

      //--------------------------------------------------------------------------------
      // After execution
      //--------------------------------------------------------------------------------
      // Alice
      await getAndCheckPartyStatus(_dvp, settlementId, _alice.address, {
        // Expected results:
        approved: true,
        etherRequired: 1_000_000n,
        etherDeposited: 0n,
        tokenStatuses: [
          {
            tokenAddress: _usdc,
            isNFT: false,
            amountOrIdRequired: 100n,
            amountOrIdApprovedForDvp: 0n,
            amountOrIdHeldByParty: TOKEN_AMOUNT_LARGE_6_DECIMALS - 100n,
          },
          {
            tokenAddress: _dai,
            isNFT: false,
            amountOrIdRequired: 2_000_000n,
            amountOrIdApprovedForDvp: 0n,
            amountOrIdHeldByParty: TOKEN_AMOUNT_LARGE_18_DECIMALS, // Alice sent & received 2m, so net is 0
          },
        ],
      });

      // Bob
      await getAndCheckPartyStatus(_dvp, settlementId, _bob.address, {
        // Expected results:
        approved: true,
        etherRequired: 1_500_000n,
        etherDeposited: 0n,
        tokenStatuses: [],
      });

      // Charlie
      await getAndCheckPartyStatus(_dvp, settlementId, _charlie.address, {
        // Expected results:
        approved: true,
        etherRequired: 0n,
        etherDeposited: 0n,
        tokenStatuses: [
          {
            tokenAddress: _dai,
            isNFT: false,
            amountOrIdRequired: 2_000_000n,
            amountOrIdApprovedForDvp: 0n,
            amountOrIdHeldByParty: TOKEN_AMOUNT_LARGE_18_DECIMALS, // Alice sent & received 2m, so net is 0
          },
        ],
      });
    });

    it("[Case 2] Should show correct statuses for parties throughout settlement lifecycle with NFTs", async () => {
      const flows = buildFlowsNftComplex(_fb);
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, false);
      const receipt = await tx.wait();
      const settlementId = findEvent(receipt, "SettlementCreated").args
        .settlementId;

      //--------------------------------------------------------------------------------
      // Before approvals
      //--------------------------------------------------------------------------------
      // Alice is sending two NFTs from _nftCat.
      await getAndCheckPartyStatus(_dvp, settlementId, _alice.address, {
        approved: false,
        etherRequired: 0n,
        etherDeposited: 0n,
        tokenStatuses: [
          {
            tokenAddress: _nftCat,
            isNFT: true,
            amountOrIdRequired: BigInt(NFT_CAT_DAISY),
            amountOrIdApprovedForDvp: 0n,
            amountOrIdHeldByParty: BigInt(NFT_CAT_DAISY),
          },
          {
            tokenAddress: _nftCat,
            isNFT: true,
            amountOrIdRequired: BigInt(NFT_CAT_BUTTONS),
            amountOrIdApprovedForDvp: 0n,
            amountOrIdHeldByParty: BigInt(NFT_CAT_BUTTONS),
          },
        ],
      });

      // Bob is sending ETH and USDC.
      await getAndCheckPartyStatus(_dvp, settlementId, _bob.address, {
        approved: false,
        etherRequired: TOKEN_AMOUNT_SMALL_18_DECIMALS,
        etherDeposited: 0n,
        tokenStatuses: [
          {
            tokenAddress: _usdc,
            isNFT: false,
            amountOrIdRequired: TOKEN_AMOUNT_SMALL_6_DECIMALS,
            amountOrIdApprovedForDvp: 0n,
            // Assume Bob starts with a large USDC balance
            amountOrIdHeldByParty: TOKEN_AMOUNT_LARGE_6_DECIMALS,
          },
        ],
      });

      // Charlie is sending one NFT from _nftDog.
      await getAndCheckPartyStatus(_dvp, settlementId, _charlie.address, {
        approved: false,
        etherRequired: 0n,
        etherDeposited: 0n,
        tokenStatuses: [
          {
            tokenAddress: _nftDog,
            isNFT: true,
            amountOrIdRequired: BigInt(NFT_DOG_FIDO),
            amountOrIdApprovedForDvp: 0n,
            amountOrIdHeldByParty: BigInt(NFT_DOG_FIDO),
          },
        ],
      });

      //--------------------------------------------------------------------------------
      // Approvals
      //--------------------------------------------------------------------------------
      // Approve settlement for each party.
      await _dvp.connect(_alice.wallet).approveSettlements([settlementId]);
      await _dvp.connect(_bob.wallet).approveSettlements([settlementId], {
        value: TOKEN_AMOUNT_SMALL_18_DECIMALS,
      });
      await _dvp.connect(_charlie.wallet).approveSettlements([settlementId]);

      // Approve tokens/NFTs for the DVP contract.
      // Alice approves her NFTs from _nftCat.
      await _nftCatToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, NFT_CAT_DAISY);
      await _nftCatToken
        .connect(_alice.wallet)
        .approve(_dvpAddress, NFT_CAT_BUTTONS);

      // Bob approves his USDC tokens.
      await _usdcToken
        .connect(_bob.wallet)
        .approve(_dvpAddress, TOKEN_AMOUNT_SMALL_6_DECIMALS);

      // Charlie approves his NFT from _nftDog.
      await _nftDogToken
        .connect(_charlie.wallet)
        .approve(_dvpAddress, NFT_DOG_FIDO);

      //--------------------------------------------------------------------------------
      // After approvals
      //--------------------------------------------------------------------------------
      // Alice: her NFTs are now approved.
      await getAndCheckPartyStatus(_dvp, settlementId, _alice.address, {
        approved: true,
        etherRequired: 0n,
        etherDeposited: 0n,
        tokenStatuses: [
          {
            tokenAddress: _nftCat,
            isNFT: true,
            amountOrIdRequired: BigInt(NFT_CAT_DAISY),
            amountOrIdApprovedForDvp: BigInt(NFT_CAT_DAISY),
            amountOrIdHeldByParty: BigInt(NFT_CAT_DAISY),
          },
          {
            tokenAddress: _nftCat,
            isNFT: true,
            amountOrIdRequired: BigInt(NFT_CAT_BUTTONS),
            amountOrIdApprovedForDvp: BigInt(NFT_CAT_BUTTONS),
            amountOrIdHeldByParty: BigInt(NFT_CAT_BUTTONS),
          },
        ],
      });

      // Bob: his ETH and USDC are now approved.
      await getAndCheckPartyStatus(_dvp, settlementId, _bob.address, {
        approved: true,
        etherRequired: TOKEN_AMOUNT_SMALL_18_DECIMALS,
        etherDeposited: TOKEN_AMOUNT_SMALL_18_DECIMALS,
        tokenStatuses: [
          {
            tokenAddress: _usdc,
            isNFT: false,
            amountOrIdRequired: TOKEN_AMOUNT_SMALL_6_DECIMALS,
            amountOrIdApprovedForDvp: TOKEN_AMOUNT_SMALL_6_DECIMALS,
            amountOrIdHeldByParty: TOKEN_AMOUNT_LARGE_6_DECIMALS,
          },
        ],
      });

      // Charlie: his NFT is now approved.
      await getAndCheckPartyStatus(_dvp, settlementId, _charlie.address, {
        approved: true,
        etherRequired: 0n,
        etherDeposited: 0n,
        tokenStatuses: [
          {
            tokenAddress: _nftDog,
            isNFT: true,
            amountOrIdRequired: BigInt(NFT_DOG_FIDO),
            amountOrIdApprovedForDvp: BigInt(NFT_DOG_FIDO),
            amountOrIdHeldByParty: BigInt(NFT_DOG_FIDO),
          },
        ],
      });

      //--------------------------------------------------------------------------------
      // Execution
      //--------------------------------------------------------------------------------
      await _dvp.connect(_alice.wallet).executeSettlement(settlementId);

      //--------------------------------------------------------------------------------
      // After execution
      //--------------------------------------------------------------------------------
      // After the settlement:
      // - Alice has sent her NFTs from _nftCat so her holdings for those tokens drop to 0.
      // - Bob’s ETH deposit is spent and his USDC holding is reduced by TOKEN_AMOUNT_SMALL_6_DECIMALS.
      // - Charlie’s NFT from _nftDog is transferred so he no longer holds it.

      // Alice: her two NFT obligations are now fulfilled.
      await getAndCheckPartyStatus(_dvp, settlementId, _alice.address, {
        approved: true,
        etherRequired: 0n,
        etherDeposited: 0n,
        tokenStatuses: [
          {
            tokenAddress: _nftCat,
            isNFT: true,
            amountOrIdRequired: BigInt(NFT_CAT_DAISY),
            amountOrIdApprovedForDvp: 0n,
            amountOrIdHeldByParty: 0n,
          },
          {
            tokenAddress: _nftCat,
            isNFT: true,
            amountOrIdRequired: BigInt(NFT_CAT_BUTTONS),
            amountOrIdApprovedForDvp: 0n,
            amountOrIdHeldByParty: 0n,
          },
        ],
      });

      // Bob: his ETH is spent and his USDC holding decreases.
      await getAndCheckPartyStatus(_dvp, settlementId, _bob.address, {
        approved: true,
        etherRequired: TOKEN_AMOUNT_SMALL_18_DECIMALS,
        etherDeposited: 0n,
        tokenStatuses: [
          {
            tokenAddress: _usdc,
            isNFT: false,
            amountOrIdRequired: TOKEN_AMOUNT_SMALL_6_DECIMALS,
            amountOrIdApprovedForDvp: 0n,
            amountOrIdHeldByParty:
              TOKEN_AMOUNT_LARGE_6_DECIMALS - TOKEN_AMOUNT_SMALL_6_DECIMALS,
          },
        ],
      });

      // Charlie: his NFT is now transferred out.
      await getAndCheckPartyStatus(_dvp, settlementId, _charlie.address, {
        approved: true,
        etherRequired: 0n,
        etherDeposited: 0n,
        tokenStatuses: [
          {
            tokenAddress: _nftDog,
            isNFT: true,
            amountOrIdRequired: BigInt(NFT_DOG_FIDO),
            amountOrIdApprovedForDvp: 0n,
            amountOrIdHeldByParty: 0n,
          },
        ],
      });
    });

    it("[Case 3] Should revert if settlement does not exist", async () => {
      await expect(
        _dvp.getSettlementPartyStatus(NOT_A_SETTLEMENT_ID, _alice.address)
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.SettlementDoesNotExist
      );
    });

    it("[Case 4] Should return empty results if party not involved in settlement", async () => {
      // Dave is not involved in this settlement
      const flows = buildFlows(_fb);
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, false);
      const receipt = await tx.wait();
      const settlementId = findEvent(receipt, "SettlementCreated").args
        .settlementId;
      const partyStatus = await _dvp.getSettlementPartyStatus(
        settlementId,
        _dave.address
      );
      expect(partyStatus.isApproved).to.be.false;
      expect(partyStatus.etherDeposited).to.equal(0n);
      expect(partyStatus.etherRequired).to.equal(0n);
      expect(partyStatus.tokenStatuses).to.be.empty;
    });

    it("[Case 5] Should achieve full coverage for party status", async () => {
      // Just to get coverage of some if-else branches in the get party status helpers
      const flows = buildFlowsCoverage(_fb);
      const cutoff = _timestamps.nowPlusDays(7);
      const tx = await _dvp
        .connect(_alice.wallet)
        .createSettlement(flows, SETTLEMENT_REF, cutoff, false);
      const receipt = await tx.wait();
      const settlementId = findEvent(receipt, "SettlementCreated").args
        .settlementId;
      const partyStatus = await _dvp.getSettlementPartyStatus(
        settlementId,
        _alice.address
      );
      expect(partyStatus.isApproved).to.be.false;
    });
  });

  describe("[Process] Send ETH directly to contract", async () => {
    it("[Case 1] Should revert if Ether is sent directly to the contract", async () => {
      await expect(
        _alice.wallet.sendTransaction({
          to: _dvpAddress,
          value: 1n,
        })
      ).to.be.revertedWithCustomError(
        _dvp,
        CUSTOM_ERRORS.DeliveryVersusPayment.CannotSendEtherDirectly
      );
    });
  });

  describe("[Function] isERC721", async () => {
    it("[Case 1] Should succeed with true for an NFT contract", async () => {
      const isERC721 = await _dvp.isERC721(_nftCat);
      expect(isERC721).to.be.true;
    });

    it("[Case 2] Should succeed with false for a non-NFT contract", async () => {
      const isERC721 = await _dvp.isERC721(_dai);
      expect(isERC721).to.be.false;
    });

    it("[Case 3] Should succeed with false for an EoA address", async () => {
      const isERC721 = await _dvp.isERC721(_alice.address);
      expect(isERC721).to.be.false;
    });
  });

  describe("[Function] isERC20", async () => {
    it("[Case 1] Should succeed with true for an ERC-20 contract", async () => {
      const isERC20 = await _dvp.isERC20(_dai);
      expect(isERC20).to.be.true;
    });

    it("[Case 2] Should succeed with false for a non ERC-20 contract", async () => {
      const isERC20 = await _dvp.isERC20(_nftCat);
      expect(isERC20).to.be.false;
    });

    it("[Case 3] Should succeed with false for an EoA address", async () => {
      const isERC20 = await _dvp.isERC20(_alice.address);
      expect(isERC20).to.be.false;
    });
  });
});
