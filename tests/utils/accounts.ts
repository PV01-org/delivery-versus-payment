import { ethers } from 'hardhat';
import { Account } from './types';
import { SignerWithAddress } from '@nomicfoundation/hardhat-ethers/signers';

export const getAccounts = async (): Promise<Account[]> => {
  const accounts: Account[] = [];

  const wallets = await getWallets();
  for (let i = 0; i < wallets.length; i++) {
    accounts.push({
      wallet: wallets[i],
      address: await wallets[i].getAddress()
    });
  }

  return accounts;
};

// NOTE ethers.signers may be a hardhat specific function
export const getWallets = async (): Promise<SignerWithAddress[]> => {
  return (await ethers.getSigners()) as SignerWithAddress[];
};
