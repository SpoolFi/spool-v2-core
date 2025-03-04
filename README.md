# Spool V2

Spool V2 is the infrastructure layer for Institutional-grade investment into DeFi.
It is decentralized middleware that allows anyone to create custom, diversified, and automated DeFi meta-strategies called “Smart Vaults", allowing users to select multiple strategies from a list of supported protocols, choose a Risk Model to assign risk scores to the selected strategies, and then set their risk appetite.

The Spool Protocol then deploys a smart contract that represents the "terms of engagement" the user has chosen. Any deposits through this smart contract will be routed to a master contract that manages deposits of all individual Smart Vaults and then to the underlying strategies via separate adapters for each supported strategy (see ).

The Spool Protocol regularly rebalances portfolios while adhering to individual terms to ensure each individual Smart Vault is optimized at all times in terms of risk-adjusted yield.

Documentation available [here](https://archit3ct.gitbook.io/spool-v2-technical-documentation/).

## Testing and coverage

### Setup

- set `.env` file
  - all tests
    - `FOUNDRY_PROFILE=default`
  - forked tests
    - `MAINNET_RPC_URL=...`
    - `ARBITRUM_RPC_URL=...`
    - `SEPOLIA_RPC_URL=...`

### Running

- locally run tests:
  - `forge test`
- forked tests:
  - `forge test --no-match-path "." --match-path "./test/forked/**`
- all tests:
  - `forge test --no-match-path "."`

### Coverage

To generate the full test coverage report, both local and fork tests need to be analyzed. Setup the `RPC_URL` environment variable as described above, and then run

```
forge coverage --report lcov --fork-url $RPC_URL
genhtml lcov.info --branch-coverage --output-dir coverage
```

The html report is then available at `./coverage/src/index.html`.

The `genhtml` tool is not available for Windows, but WSL can be used to bypass this limitation.

### Test deployment

To locally test mainnet deployment, set `PRIVATE_KEY` in the `.env` file. Use `.env.sample` as a guide.

Then run anvil in one terminal set to fork the mainnet:

```
anvil --fork-url <MAINNET_FORK_URL>
```
where you have to provide your fork url. Finally you can execute deployment script by

```
forge script script/LocalMainnetInitialSetup.s.sol --fork-url http://localhost:8545 --broadcast
```

The addresses of deployed contracts will be listed in the `deploy/local-mainnet.contracts.json` file, and the detailed broadcast in the `broadcast/LocalMainnetInitialSetup.s.sol/` folder.

deploy and verify on Tenderly (`mainnet-staging`) with the following:

- set `FOUNDRY_PROFILE` in `.env` to `mainnet-staging`

```
forge script MainnetInitialSetup --rpc-url $TENDERLY_TESTNET_URL \
 --slow \
 --broadcast \
 --skip-simulation \
 --verify \
 --etherscan-api-key $TENDERLY_API_KEY \
 --verifier-url="https://api.tenderly.co/api/v1/account/solidant-org/project/spool-v2/etherscan/verify/testnet/${TENDERLY_ARBITRUM_TESTNET_RESOURCE_ID}"
```
where:
- `TENDERLY_TESTNET_URL`: RPC URL of the Tenderly mainnet staging environment.
- `TENDERLY_API_KEY`: Key that permits deployments and verification.
- `TENDERLY_TESTNET_RESOURCE_ID`: Resource ID of the Tenderly virtual testnet (for Mainnet).

The addresses of deployed contracts will be listed in the `deploy/mainnet-staging.contracts.json` file, and the detailed broadcast in the `broadcast/mainnet-staging/` folder.


deploy and verify on Tenderly (`arbitrum-staging`) with the following:

- set `FOUNDRY_PROFILE` in `.env` to `arbitrum-staging`

```
forge script ArbitrumInitialSetup --rpc-url $TENDERLY_ARBITRUM_TESTNET_URL \
 --slow \
 --broadcast \
 --skip-simulation \
 --verify \
 --etherscan-api-key $TENDERLY_API_KEY \
 --verifier-url="https://api.tenderly.co/api/v1/account/solidant-org/project/spool-v2/etherscan/verify/testnet/${TENDERLY_ARBITRUM_TESTNET_RESOURCE_ID}"
```
- `TENDERLY_ARBITRUM_TESTNET_0`: RPC URL of the Tenderly arbitrum staging environment.
- `TENDERLY_API_KEY`: Key that permits deployments and verification.
- `TENDERLY_ARBITRUM_TESTNET_RESOURCE_ID`: Resource ID of the Tenderly virtual testnet (for Arbitrum).

The addresses of deployed contracts will be listed in the `deploy/mainnet-staging.contracts.json` file, and the detailed broadcast in the `broadcast/mainnet-staging/` folder.

## Smart Contract Overview

### SmartVaultManager.sol

This is the main entry point for all user interactions and delegates to other contracts.

- DepositManager.sol - deposit logic
- WithdrawalManager.sol - Withdrawal Logic

### MasterWallet.sol

This holds the funds for:

- DHW to pick up and funnel to underlying protocols.
- The user to claim after funds were successfully extracted from underlying protocols (on withdrawal).

### SmartVault.sol

Each Vault has its own `SmartVault.sol` deployment.
Implements ERC20 SVTs (Smart Vault Tokens) which represent the user's share in the Vault.
Implements ERC1155 for deposit and withdrawal of NFTs.
NFTs wrap the SVTs created and in turn can be burned to receive those SVTs back.
These can be transferred by holders depending on applicable Guards in place.

### Strategy.sol

This is the underlying protocol adapter abstraction.

### AssetGroupRegistry.sol

Asset groups are combinations of tokens that users can deposit into Vaults/Strategies.
These have to be registered and whitelisted.

### AccessControl.sol

This configures system-wide roles.
Also configures Smart Vault specific roles.
For more details see `./src/access/Roles.sol`.

### RewardManager.sol

This  Smart contract enables vault creators to configure custom Smart Vault rewards.
For example, a Vault also emits "token X" in addition to the yield generated through underlying protocols.
Rewards are calculated off-chain and claimed using `RewardPool.sol` using Merkle proofs.

### SmartVaultFactory.sol

Creates and registers new Smart Vaults.

### DepositSwap.sol

Deposits can be routed through this contract to swap assets before they reach the Smart Vault.
E.G. the user holds DAI but would like to join an ETH/USDC Smart Vault.

### GuardManager.sol

- Configures Guards for Smart Vaults.
- Runs pre-configured Guards for Smart Vaults.

### ActionManager.sol

- Configures Actions for Smart Vaults.
- Runs Actions for Smart Vaults
  Licensing
  The primary license for Spool is the Business Source License 1.1 (BUSL-1.1), see LICENSE.

## Licensing

The primary license for Spool is the Business Source License 1.1 (`BUSL-1.1`), see [`LICENSE`](./LICENSE).

### Exceptions

- All files in src/ are licensed under the license they were originally published with (as indicated in their SPDX headers)
- All files in test/ are licensed under MIT.
