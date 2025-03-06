import { DeliveryVersusPaymentV1 } from '@typechain/contracts/dvp/V1/DeliveryVersusPaymentV1';
import { IDeliveryVersusPaymentV1 } from '@typechain/contracts/dvp/V1/IDeliveryVersusPaymentV1';
import { expect } from 'chai';
import { time } from '@nomicfoundation/hardhat-toolbox/network-helpers';
import { ZeroAddress } from 'ethers';

type Flow = IDeliveryVersusPaymentV1.FlowStruct;

/**
 * Parties, tokens, constants for flow construction
 */
export type FlowBuilder = Readonly<{
  _alice: { address: string };
  _bob: { address: string };
  _charlie: { address: string };
  _dave: { address: string };
  _usdc: string;
  _eth: string;
  _dai: string;
  _nftCat: string;
  _nftDog: string;
  NFT_CAT_DAISY: number;
  NFT_CAT_BUTTONS: number;
  NFT_DOG_FIDO: number;
  TOKEN_AMOUNT_SMALL_6_DECIMALS: bigint;
  TOKEN_AMOUNT_SMALL_18_DECIMALS: bigint;
}>;

export async function moveInTime(seconds: number) {
  await time.increase(seconds);
}

export type PartyStatusExpectedValues = {
  approved: boolean;
  etherRequired: bigint;
  etherDeposited: bigint;
  tokenStatuses: {
    tokenAddress: string;
    isNFT: boolean;
    amountOrIdRequired: bigint;
    amountOrIdApprovedForDvp: bigint;
    amountOrIdHeldByParty: bigint;
  }[];
};

export async function getAndCheckPartyStatus(
  dvp: DeliveryVersusPaymentV1,
  settlementId: number,
  partyAddress: string,
  expected: PartyStatusExpectedValues
) {
  const {
    isApproved: actualApproved,
    etherRequired: actualEtherRequired,
    etherDeposited: actualEtherDeposited,
    tokenStatuses: actualTokenStatuses
  } = await dvp.getSettlementPartyStatus(settlementId, partyAddress);

  // Check booleans & ETH
  expect(actualApproved).to.equal(expected.approved, 'approved mismatch');
  expect(actualEtherRequired).to.equal(expected.etherRequired, 'etherRequired mismatch');
  expect(actualEtherDeposited).to.equal(expected.etherDeposited, 'etherDeposited mismatch');

  // Check token status array
  expect(actualTokenStatuses.length).to.equal(expected.tokenStatuses.length, 'tokenStatus length mismatch');
  for (let i = 0; i < expected.tokenStatuses.length; i++) {
    const exp = expected.tokenStatuses[i];
    const act = actualTokenStatuses[i];
    expect(act.tokenAddress).to.equal(exp.tokenAddress, `tokenAddress mismatch at index ${i}`);
    expect(act.isNFT).to.equal(exp.isNFT, `token isNFT mismatch at index ${i}`);
    expect(act.amountOrIdRequired).to.equal(exp.amountOrIdRequired, `token amountRequired mismatch at index ${i}`);
    expect(act.amountOrIdApprovedForDvp).to.equal(
      exp.amountOrIdApprovedForDvp,
      `token amountApprovedForDvp mismatch at index ${i}`
    );
    expect(act.amountOrIdHeldByParty).to.equal(
      exp.amountOrIdHeldByParty,
      `token amountHeldByParty mismatch at index ${i}`
    );
  }
}

export function buildFlows(fb: FlowBuilder): Flow[] {
  const { _alice, _bob, _charlie, _usdc, _eth, _dai, TOKEN_AMOUNT_SMALL_6_DECIMALS, TOKEN_AMOUNT_SMALL_18_DECIMALS } =
    fb;
  return [
    {
      from: _alice.address,
      to: _bob.address,
      token: _usdc,
      isNFT: false,
      amountOrId: TOKEN_AMOUNT_SMALL_6_DECIMALS
    },
    {
      from: _bob.address,
      to: _charlie.address,
      token: _eth,
      isNFT: false,
      amountOrId: TOKEN_AMOUNT_SMALL_18_DECIMALS
    },
    {
      from: _charlie.address,
      to: _alice.address,
      token: _dai,
      isNFT: false,
      amountOrId: TOKEN_AMOUNT_SMALL_18_DECIMALS
    }
  ];
}

export function buildFlowsMixed(fb: FlowBuilder): Flow[] {
  const {
    _alice,
    _bob,
    _charlie,
    _nftCat,
    _eth,
    _usdc,
    NFT_CAT_DAISY,
    TOKEN_AMOUNT_SMALL_6_DECIMALS,
    TOKEN_AMOUNT_SMALL_18_DECIMALS
  } = fb;
  return [
    {
      from: _alice.address,
      to: _bob.address,
      token: _nftCat,
      isNFT: true,
      amountOrId: NFT_CAT_DAISY
    },
    {
      from: _bob.address,
      to: _charlie.address,
      token: _eth,
      isNFT: false,
      amountOrId: TOKEN_AMOUNT_SMALL_18_DECIMALS
    },
    {
      from: _charlie.address,
      to: _alice.address,
      token: _usdc,
      isNFT: false,
      amountOrId: TOKEN_AMOUNT_SMALL_6_DECIMALS
    }
  ];
}

export function buildFlowsComplex(fb: FlowBuilder): Flow[] {
  const { _alice, _bob, _charlie, _usdc, _eth, _dai } = fb;
  return [
    {
      from: _alice.address,
      to: _bob.address,
      token: _usdc,
      isNFT: false,
      amountOrId: 100
    },
    {
      from: _bob.address,
      to: _charlie.address,
      token: _eth,
      isNFT: false,
      amountOrId: 1000000
    },
    {
      from: _charlie.address,
      to: _alice.address,
      token: _dai,
      isNFT: false,
      amountOrId: 2000000
    },
    {
      from: _alice.address,
      to: _bob.address,
      token: _eth,
      isNFT: false,
      amountOrId: 1000000
    },
    {
      from: _bob.address,
      to: _charlie.address,
      token: _eth,
      isNFT: false,
      amountOrId: 500000
    },
    {
      from: _alice.address,
      to: _charlie.address,
      token: _dai,
      isNFT: false,
      amountOrId: 2000000
    }
  ];
}

export function buildFlowsCoverage(fb: FlowBuilder): Flow[] {
  const { _alice, _bob, _charlie, _dave, _usdc, _dai } = fb;
  return [
    {
      from: _alice.address,
      to: _bob.address,
      token: _usdc,
      isNFT: false,
      amountOrId: 1
    },
    {
      from: _alice.address,
      to: _charlie.address,
      token: _usdc,
      isNFT: false,
      amountOrId: 1
    },
    {
      from: _alice.address,
      to: _dave.address,
      token: _dai,
      isNFT: false,
      amountOrId: 1
    }
  ];
}

export function buildFlowsNftSimple(fb: FlowBuilder): Flow[] {
  const { _alice, _bob, _nftCat, NFT_CAT_DAISY } = fb;
  return [
    {
      from: _alice.address,
      to: _bob.address,
      token: _nftCat,
      isNFT: true,
      amountOrId: NFT_CAT_DAISY
    }
  ];
}

export function buildFlowsERC20Simple(fb: FlowBuilder): Flow[] {
  const { _alice, _bob, _usdc, TOKEN_AMOUNT_SMALL_6_DECIMALS } = fb;
  return [
    {
      from: _alice.address,
      to: _bob.address,
      token: _usdc,
      isNFT: false,
      amountOrId: TOKEN_AMOUNT_SMALL_6_DECIMALS
    }
  ];
}

export function buildFlowsEthSimple(fb: FlowBuilder): Flow[] {
  const { _alice, _bob, TOKEN_AMOUNT_SMALL_18_DECIMALS } = fb;
  return [
    {
      from: _alice.address,
      to: _bob.address,
      token: ZeroAddress,
      isNFT: false,
      amountOrId: TOKEN_AMOUNT_SMALL_18_DECIMALS
    }
  ];
}

export function buildFlowsNftComplex(fb: FlowBuilder): Flow[] {
  const {
    _alice,
    _bob,
    _charlie,
    _usdc,
    _eth,
    _nftCat,
    _nftDog,
    NFT_DOG_FIDO,
    NFT_CAT_DAISY,
    NFT_CAT_BUTTONS,
    TOKEN_AMOUNT_SMALL_6_DECIMALS,
    TOKEN_AMOUNT_SMALL_18_DECIMALS
  } = fb;

  return [
    {
      from: _alice.address,
      to: _bob.address,
      token: _nftCat,
      isNFT: true,
      amountOrId: NFT_CAT_DAISY
    },
    {
      from: _alice.address,
      to: _bob.address,
      token: _nftCat,
      isNFT: true,
      amountOrId: NFT_CAT_BUTTONS
    },
    {
      from: _bob.address,
      to: _charlie.address,
      token: _eth,
      isNFT: false,
      amountOrId: TOKEN_AMOUNT_SMALL_18_DECIMALS
    },
    {
      from: _bob.address,
      to: _charlie.address,
      token: _usdc,
      isNFT: false,
      amountOrId: TOKEN_AMOUNT_SMALL_6_DECIMALS
    },
    {
      from: _charlie.address,
      to: _alice.address,
      token: _nftDog,
      isNFT: true,
      amountOrId: NFT_DOG_FIDO
    }
  ];
}

export function buildFlowsMixedLarge(fb: FlowBuilder): Flow[] {
  const {
    _alice,
    _bob,
    _charlie,
    _usdc,
    _eth,
    _nftCat,
    _nftDog,
    NFT_DOG_FIDO,
    NFT_CAT_DAISY,
    NFT_CAT_BUTTONS,
    TOKEN_AMOUNT_SMALL_6_DECIMALS,
    TOKEN_AMOUNT_SMALL_18_DECIMALS
  } = fb;

  return [
    {
      from: _alice.address,
      to: _bob.address,
      token: _nftCat,
      isNFT: true,
      amountOrId: NFT_CAT_DAISY
    },
    {
      from: _alice.address,
      to: _bob.address,
      token: _nftCat,
      isNFT: true,
      amountOrId: NFT_CAT_BUTTONS
    },
    {
      from: _bob.address,
      to: _charlie.address,
      token: _eth,
      isNFT: false,
      amountOrId: TOKEN_AMOUNT_SMALL_18_DECIMALS
    },
    {
      from: _bob.address,
      to: _charlie.address,
      token: _usdc,
      isNFT: false,
      amountOrId: TOKEN_AMOUNT_SMALL_6_DECIMALS
    },
    {
      from: _charlie.address,
      to: _alice.address,
      token: _nftDog,
      isNFT: true,
      amountOrId: NFT_DOG_FIDO
    },
    {
      from: _alice.address,
      to: _bob.address,
      token: _nftCat,
      isNFT: true,
      amountOrId: NFT_CAT_DAISY
    },
    {
      from: _alice.address,
      to: _bob.address,
      token: _nftCat,
      isNFT: true,
      amountOrId: NFT_CAT_BUTTONS
    },
    {
      from: _bob.address,
      to: _charlie.address,
      token: _eth,
      isNFT: false,
      amountOrId: TOKEN_AMOUNT_SMALL_18_DECIMALS
    },
    {
      from: _bob.address,
      to: _charlie.address,
      token: _usdc,
      isNFT: false,
      amountOrId: TOKEN_AMOUNT_SMALL_6_DECIMALS
    },
    {
      from: _charlie.address,
      to: _alice.address,
      token: _nftDog,
      isNFT: true,
      amountOrId: NFT_DOG_FIDO
    },
    {
      from: _bob.address,
      to: _charlie.address,
      token: _usdc,
      isNFT: false,
      amountOrId: TOKEN_AMOUNT_SMALL_6_DECIMALS
    },
    {
      from: _charlie.address,
      to: _alice.address,
      token: _nftDog,
      isNFT: true,
      amountOrId: NFT_DOG_FIDO
    }
  ];
}
