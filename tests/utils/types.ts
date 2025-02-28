import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

export type Account = {
  address: string;
  wallet: SignerWithAddress;
  description?: string;
};
