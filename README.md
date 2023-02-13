# Spool V2

Spool V2 is the infrastructure layer for Institutional-grade investment into DeFi.
It is decentralized middleware that allows anyone to create custom, diversified, and automated DeFi meta-strategies called “Smart Vaults", allowing users to select multiple strategies from a list of supported protocols, choose a Risk Model to assign risk scores to the selected strategies, and then set their risk appetite.

The Spool Protocol then deploys a smart contract that represents the "terms of engagement" the user has chosen. Any deposits through this smart contract will be routed to a master contract that manages deposits of all individual Smart Vaults and then to the underlying strategies via separate adapters for each supported strategy (see ).

The Spool Protocol regularly rebalances portfolios while adhering to individual terms to ensure each individual Smart Vault is optimized at all times in terms of risk-adjusted yield.

Documentation available [here](https://archit3ct.gitbook.io/spool-v2-technical-documentation/).

## Testing and coverage

### Generate a coverage report with

```
forge coverage --fork-url $RPC_URL --report lcov
genhtml lcov.info --branch-coverage --output-dir coverage
```

Browse the coverage report by opening `./coverage/src/index.html`.

### Fork testing in folder `test/forked`

`forge t --fork-url $RPC_URL --match-path "./test/forked/**/*.t.sol"`

Or on windows you can use:

```
.\source.ps1
forge test --fork-url $Env:RPC_URL --match-path "./test/forked/**/*.t.sol"
```

**Note:** load RPC_URL variable from `.env` into environment.

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
