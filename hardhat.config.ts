import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.28',
        settings: {
          optimizer: { enabled: true, runs: 200 },
          evmVersion: 'cancun'
        }
      }
    ]
  },
  paths: {
    tests: './tests'
  },
  networks: {
    hardhat: {
      initialBaseFeePerGas: 0,
      chainId: 31337,
      accounts: {
        mnemonic: 'test test test test test test test test test test test junk',
        accountsBalance: '1000000000000000000000000000000'
      }
    }
  },
  typechain: {
    outDir: 'typechain',
    target: 'ethers-v6'
  }
};

export default config;
