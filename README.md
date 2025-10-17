# Delivery Versus Payment <!-- omit from toc -->

![Build Status](https://github.com/PV01-org/delivery-versus-payment/actions/workflows/ci.yml/badge.svg)
![GitHub issues](https://img.shields.io/github/issues/PV01-org/delivery-versus-payment)
![GitHub pull requests](https://img.shields.io/github/issues-pr/PV01-org/delivery-versus-payment)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/PV01-org/delivery-versus-payment)

- [Description](#description)
  - [Features](#features)
  - [Terminology](#terminology)
- [Installation](#installation)
- [Commands](#commands)
- [Deployed Addresses](#deployed-addresses)
  - [Further Deployments](#further-deployments)
- [Workflow Summary](#workflow-summary)
  - [Create a Settlement](#create-a-settlement)
  - [Approve a Settlement](#approve-a-settlement)
  - [Execute a Settlement](#execute-a-settlement)
  - [Changes](#changes)
  - [Gas Usage](#gas-usage)
  - [Griefing](#griefing)
  - [Reentrancy Protection](#reentrancy-protection)
- [Sequence Diagram](#sequence-diagram)
- [Events](#events)
- [Contributing](#contributing)
- [Roadmap](#roadmap)
- [License](#license)

## Description
This repo is a permissionless implementation of the Delivery Versus Payment (DVP) protocol supporting ERC-20, ERC-721, and Ether transfers. Developed and actively used by [PV01](https://pv0.one), this project is open-sourced under the MIT [license](LICENSE) and provided as a public good.

### Features
 - Non-upgradeable, singleton [Delivery Versus Payment contract](contracts/dvp/V1/DeliveryVersusPaymentV1.sol).
 - Allows atomic swaps of an arbitrary number of assets between an arbitrary number of parties.
 - Permissionless, anyone can create and execute these swaps, so long as involved parties have approved.
 - Supports assets including native ETH, ERC-20 and ERC-721.
 - [Helper contract](contracts/dvp/V1/DeliveryVersusPaymentV1HelperV1.sol) provides search functionality for off-chain use.

### Terminology
 - Party: An address involved as either a `from` or `to` in an asset movement.
 - Flow: A movement of a single asset between two parties.
 - Asset: Ether, ERC-20 or ERC-721 token.
 - Settlement: A collection of an arbitrary number of flows, uniquely identified by a Settlement id. All settlements live in the singleton contract.

## Installation
```
git clone --recurse-submodules https://github.com/PV01-org/delivery-versus-payment.git
cd delivery-versus-payment
forge build
```

## Commands
The following CLI commands are available:
| # | Action         | Usage                         | Description                               |
|---|----------------|-------------------------------|-------------------------------------------|
| 1 | Compile        | `forge build`                 | Compile Solidity smart contracts.         |
| 2 | Test           | `forge test --summary`        | Run smart contract tests.                 |
| 3 | Coverage       | `forge coverage --ir-minimum` | Run tests and generate coverage reports.  |
| 4 | Gas Estimate   | `forge test --gas-report`     | Run tests with gas reporting.             |
| 5 | Sizer          | `forge build --sizes`         | Report contract size.                     |

## Deployed Addresses
The DVP contracts are available at the following addresses. Since the solution is permissionless, they can be freely used as they are, without needing further contract deployments. To deploy new contracts see [Further Deployments](#further-deployments).
| Chain       | Instance          | Contract Block Explorer Link     | Address                                      |
|-------------|-------------------|----------------------------------|----------------------------------------------|
| Arbitrum    | Testnet (Sepolia) | [DeliveryVersusPaymentV1](https://sepolia.arbiscan.io/address/0xA19B617507fef9866Fc7465933f7e3D48C7Ca03C)          | `0xA19B617507fef9866Fc7465933f7e3D48C7Ca03C` |
| Arbitrum    | Testnet (Sepolia) | [DeliveryVersusPaymentV1HelperV1](https://sepolia.arbiscan.io/address/0x83096F52F2C20373C11ADa557FD87DA8Db2b150a)  | `0x83096F52F2C20373C11ADa557FD87DA8Db2b150a` |
| Avalanche   | Mainnet           | [DeliveryVersusPaymentV1](https://snowtrace.io/address/0xE87c95AB6a3e11e16E72A2b6234454Bb29130C95)          | `0xE87c95AB6a3e11e16E72A2b6234454Bb29130C95` |
| Avalanche   | Mainnet           | [DeliveryVersusPaymentV1HelperV1](https://snowtrace.io/address/0xeDFDecC5e1932dd3D99Ee87f370FA89E1901F4F9)  | `0xeDFDecC5e1932dd3D99Ee87f370FA89E1901F4F9` |
| Avalanche   | Testnet (Fuji)    | [DeliveryVersusPaymentV1](https://testnet.snowtrace.io/address/0xa70404d8ca272bE8bAA48A4b83ED94Db17068e05)          | `0xa70404d8ca272bE8bAA48A4b83ED94Db17068e05` |
| Avalanche   | Testnet (Fuji)    | [DeliveryVersusPaymentV1HelperV1](https://testnet.snowtrace.io/address/0x8DdC71B21889dd727D7aC5432799406F2901E74a)  | `0x8DdC71B21889dd727D7aC5432799406F2901E74a` |
| Ethereum    | Mainnet           | DeliveryVersusPaymentV1          | `tbc`                                        |
| Ethereum    | Mainnet           | DeliveryVersusPaymentV1HelperV1  | `tbc`                                        |
| Ethereum    | Testnet (Sepolia) | [DeliveryVersusPaymentV1](https://sepolia.etherscan.io/address/0x0DB7eb1E62514625E03AdE35E60df74Fb8e4E36a)          | `0x0DB7eb1E62514625E03AdE35E60df74Fb8e4E36a` |
| Ethereum    | Testnet (Sepolia) | [DeliveryVersusPaymentV1HelperV1](https://sepolia.etherscan.io/address/0xE988E4A78DD4717C0E1f2182C257A459Fe06DF68)  | `0xE988E4A78DD4717C0E1f2182C257A459Fe06DF68` |
| Polygon     | Mainnet           | [DeliveryVersusPaymentV1](https://polygonscan.com/address/0xFBdA0E404B429c878063b3252A2c2da14fe28e7f)          | `0xFBdA0E404B429c878063b3252A2c2da14fe28e7f` |
| Polygon     | Mainnet           | [DeliveryVersusPaymentV1HelperV1](https://polygonscan.com/address/0x662E81BCfF1887C4F73f8086E9D0d590F85A7f1E)  | `0x662E81BCfF1887C4F73f8086E9D0d590F85A7f1E` |

### Further Deployments
To deploy further copies of individual contracts, use the deploy scripts in the `./script` folder, for example:

```bash
forge script script/DeployDvp.s.sol --rpc-url <$RPC_URL> --private-key <$PRIVATE_KEY> --broadcast
```

To deploy contracts on many chains follow these steps:
1. Define the network names to deploy to in `foundry.toml`.
2. Copy `.env.template` to `.env` and maintain environment variables. Network names should match those defined in `foundry.toml`.
3. Edit the deploy script `deploy-multi-chain.sh` in the `.scripts` folder. Change the variable called `NETWORKS` to contain the network names you want to deploy to.
4. Run:
```bash
./scripts/deploy-multi-chain.sh`
```

## Workflow Summary
### Create a Settlement
A settlement is collection of intended value transfers (Flows) between parties, along with a free text reference, a deadline (cutoff date) and an auto-settlement flag indicating if settlement should be immediately processed after final approval received. ERC-20, ERC-721 and Ether transfers are supported. For example a settlement could include the following 3 flows, be set to expire in 1 week, and be auto-settled when all `from` parties (sender addresses) have approved:

|  From    |    | To      | AmountOrId  | Token  | isNFT |
|----------|----|---------|-------------|--------|-------|
|  Alice   | -> | Bob     | 1           | ETH    | false |
|  Bob     | -> | Charlie | 400         | TokenA | false |
|  Charlie | -> | Alice   | 500(id)     | TokenB | true  |

- If a token claims to be an NFT and is not, the creation will revert.
- If a token claims to be an ERC20, but doesn't implement `decimals()`, the creation will revert.
- Anyone can create a settlement involving any parties and any asset.

### Approve a Settlement
Each party who is a `from` address in one or more flows needs to approve the settlement before it can proceed. They do this by calling `approveSettlements()` and including their necessary total ETH deposit if their flows involve sending ETH. ERC-20 and ERC-721 tokens are not deposited upfront, they only need transfer approval before execution. If a settlement is marked as `isAutoSettled`:
 - the settlement will be executed automatically after all approvals are in place, the gas cost being borne by the last approver.
 - if settlement approval succeeds, but auto-execution fails, the entire transaction is not reverted. The approval remains on-chain, only the settlement execution is reverted.

### Execute a Settlement
Anyone can call `executeSettlement()` before the cutoff date, if all approvals are in place. At execution time the contract makes the transfers in an atomic, all or nothing, manner. If any Flow transfer fails the entire settlement is reverted.

### Changes
If a party changes their mind before the settlement is fully executed — and before the cutoff date — they can revoke their approval by calling `revokeApprovals()`. This returns any deposited ETH back to them and removes their approval. Once expired a settlement can no longer be executed, any ETH deposited can be withdrawn by each party using `withdrawETH()`.

### Gas Usage
There are many unbounded loops in this contract, by design. There is no limit on the number of flows in a settlement, nor on how many settlements can be batch processed (for functions that receive an array of settlementIds). The current chain's block gas limit acts as a cap. In every case it is the caller's responsibility to ensure that the gas requirement can be met.

### Griefing
It is acknowledged that bad actors could be annoying by creating flows with fake tokens, or flows with tokens that would intentionally revert when the settlement is executed, and so making a settlement impossible to process. These bad actors could potentially trick other parties into locking ETH into a settlement that could never be processed. There is no financial loss (gas fees excepted) because when other parties discover the ruse, they can withdraw their approval and withdraw their ETH.

### Reentrancy Protection
Settlement approval can be done in batches. Settlement execution can potentially be triggered inside that (if auto-settle is switched on and a party is giving the final approval). Settlement execution can make many external calls to process transfers of assets. These patterns lend themselves well to reentrancy, which is protected against as follows:

| Function             | Reentrancy Protection     |
|----------------------|---------------------------|
| approveSettlements() | OZ nonReentrant modifer   |
| createSettlement()   | No external calls made    |
| executeSettlement()  | OZ nonReentrant modifer   |
| revokeApprovals()    | OZ nonReentrant modifer   |
| withdrawETH()        | OZ nonReentrant modifer   |

There are some subtleties inside the protection for `approveSettlements()` and `executeSettlement()`, explained [here](REENTRANCY.md).

## Sequence Diagram
Sequence diagram for a happy path process though a settlement with auto-settle enabled.
![flow](docs/dvp-transaction-flow.png)

## Events
Topic0 values for events are:

| Event                                                       | Topic0                                                             |
|-------------------------------------------------------------|--------------------------------------------------------------------|
| ETHReceived(address,uint256)                                | 0xbfe611b001dfcd411432f7bf0d79b82b4b2ee81511edac123a3403c357fb972a |
| ETHWithdrawn(address,uint256)                               | 0x94b2de810873337ed265c5f8cf98c9cffefa06b8607f9a2f1fbaebdfbcfbef1c |
| SettlementApprovalRevoked(uint256,address)                  | 0x96c5a579760c144ad93a5c19d41440d5185ba0451704c0ac7cb22488d8735ac2 |
| SettlementApproved(uint256,address)                         | 0x7f89b61c53062fb158619c7b66552eabdfb0e1d37c439a62c2d2b5a657bcea93 |
| SettlementAutoExecutionFailedOther(uint256,address,bytes)   | 0x63c222ac809d589e48426985c6af11739f936b405e0a78a920fbae6565c07497 |
| SettlementAutoExecutionFailedPanic(uint256,address,uint256) | 0x3c4e728bba5a6c57290cee894ede5970e12dc7d459808344b14cec9a956f1dc2 |
| SettlementAutoExecutionFailedReason(uint256,address,string) | 0xe1c01819733d746479549271d3a51445514b8f678614d50ad34d305c67b83d9c |
| SettlementCreated(uint256,address)                          | 0x3c521c92800f95c83d088ee8c520c5b47b3676958e48a985fe1d45d7cf6dbd78 |
| SettlementExecuted(uint256,address)                         | 0xf059ff22963b773739a912cc5c0f2f358be1a072c66ba18e2c31e503fd012195 |

## Linting and pre-commit
This repository uses pre-commit to run lightweight checks and enforce a standard Solidity code format via Foundry.

Setup (one-time):
- Install pre-commit (choose one):
  - pipx: `pipx install pre-commit`
  - pip: `pip install --user pre-commit`
  - Homebrew (macOS): `brew install pre-commit`
- Ensure Foundry is installed and available in your PATH: https://book.getfoundry.sh/getting-started/installation
- Enable hooks in this repo: `pre-commit install`

Usage:
- Run on all files: `pre-commit run --all-files`
- On commit, hooks will run automatically.
- The Solidity formatter runs in check mode (`forge fmt --check`). If formatting fails, fix with: `forge fmt`

Formatting standard:
- Uses Foundry's standard formatter configured in `foundry.toml` under `[fmt]` (e.g., `line_length = 120`, `tab_width = 2`).

## Contributing
See [CONTRIBUTING.md](CONTRIBUTING.md) for more details.

## Roadmap
See [ROADMAP.md](ROADMAP.md) for more details.

## License
This project is licensed under the terms of the [LICENSE](LICENSE).
