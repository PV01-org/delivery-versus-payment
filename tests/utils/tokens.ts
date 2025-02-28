import { AssetToken__factory } from '../../typechain/factories/contracts/mock';
import { NFT__factory } from '../../typechain/factories/contracts/mock';
import { AssetToken } from '@typechain/contracts/mock/AssetToken';
import { NFT } from '@typechain/contracts/mock/NFT';
import { Account } from '../utils/types';

export async function createToken(owner: Account, name: string, symbol: string, decimals: number): Promise<AssetToken> {
  const tx = await new AssetToken__factory(owner.wallet).deploy(name, symbol, decimals);
  await tx.waitForDeployment();
  return tx;
}

export async function createNFT(owner: Account, name: string, symbol: string): Promise<NFT> {
  const tx = await new NFT__factory(owner.wallet).deploy(name, symbol);
  await tx.waitForDeployment();
  return tx;
}
