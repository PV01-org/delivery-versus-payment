import '@nomicfoundation/hardhat-ethers';
import '@nomicfoundation/hardhat-toolbox';
import '@typechain/hardhat';
import 'hardhat-contract-sizer';
import 'hardhat-deploy';
import { HardhatUserConfig } from 'hardhat/config';

interface HardhatUserConfigExtended extends HardhatUserConfig {
  typechain: {
    outDir: string;
    target: string;
  };
  gasReporter: {
    enabled: boolean;
  };
}

const config: HardhatUserConfigExtended = {
  solidity: {
    compilers: [
      {
        version: '0.8.28',
        settings: {
          optimizer: { enabled: true, runs: 1000000 },
          evmVersion: 'cancun'
        }
      }
    ],
    overrides: {
      'contracts/dvp/V1/DeliveryVersusPaymentV1HelperV1.sol': {
        version: '0.8.28',
        settings: {
          optimizer: { enabled: true, runs: 1 },
          evmVersion: 'cancun'
        }
      }
    }
  },
  paths: {
    tests: './tests'
  },
  namedAccounts: {
    owner: 0,
    user: 1
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
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS === 'true'
  }
};

export default config;
