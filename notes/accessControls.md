# Code Access Controls

In order for the Spool V2 Ecosystem to work there's a subset of roles and owners that can alter state and hold certain privileges. A list of these access controls is compiled below:

## Role: *SpoolAdmin (Spool DAO)*

### Who controls this role?

The Spool DAO Multisignature Wallet, which acts exclusively on the conclusion of Snapshot Votes.

Spool DAO Multisignature Wallet: `0x4e736b96920a0f305022CBaAea493Ce7e49Eee6C`

* The on-chain execution of Snapshot votes will be implemented.

* This is the most powerful role in the Spool Ecosystem and as such should be the most protected. 

* These actions are not called often. 

* As the root role, every rolled action in the system is callable by it. The actions listed below are just the explicit actions listed for this role. 

### What actions can this role take?

#### `ActionManager.sol`

* `whitelistAction`: permit the use of an action on smart vaults. 

#### `AssetGroupRegistry.sol`

* `allowToken`: permit a token to be used in an `AssetGroup` for a smart vault.

* `allowTokenBatch`: like `allowToken`, but for multiple tokens.

* `registerAssetGroup`: permit a group of tokens (`AssetGroup`) to be used for a smart vault.

#### `ConvexStrategy.sol`

* `setExtraRewards`: enable this strategy to collect extra rewards, if available.

#### `RewardManager.sol`

* `forceRemoveReward`: forcably remove a smart vault reward. Intended to be used in case a reward token ceases to work.

* `removeFromBlacklist`: re-enable a previously removed reward.

#### `StrategyManualYieldVerifier.sol`

* `setPositiveYieldLimit`: For strategies where APY must be manually set by the DoHardWorker, set the maximum APY allowed to be set.

* `setNegativeYieldLimit`: For strategies where APY must be manually set by the DoHardWorker, set the minimum APY allowed to be set.

#### `StrategyRegistry.sol`

* `setEmergencyWithdrawalWallet`: set the wallet to which funds collected via the emergency withdraw procedure will go to.

* `registerStrategy`: Following strategy deployment, adds the strategy to the system.

* `setEcosystemFee`: Set the fee percentage for the ecosystem.

* `setEcosystemFeeReceiver`: Set the address of the ecosystem.

* `setTreasuryFee`: Set the fee percentage for the treasury.

* `setTreasuryFeeReceiver`: Set the address of the treasury.

#### `Swapper.sol`

* `updateExchangeAllowlist`: for strategies where the DoHardWorker must specify swap parameters, update the allowable exchanges for which we can swap funds.

#### `UsdPriceFeedManager.sol`

* `setAsset`: Sets an asset for which the system can use to get prices in USD.

#### `SmartVaultManager.sol`

* `recoverPendingDeposits`: Sends pending deposits on a smart vault to the emergency withdrawal wallet, in the case of an issue with the smart vault.

* `removeStrategyFromVaults`: remove a strategy from a set of specified vaults.

## Role: *Smart Vault Integrator*

### Who controls this role?

The owner of this role is the `SmartVaultFactory` contract. The roles here are to restrict the specified functions to the Smart Vault initialization phase.
Grants permission to integrate a new smart vault into the Spool ecosystem.

### What actions can this role take?

#### `ActionManager.sol`

* `setActions`: permit a smart vault to perform a set of actions. actions must be whitelisted. 

#### `GuardManager.sol`

* `setGuards`: restrict a smart vault by a set of predefined guards.

#### `RiskManager.sol`

* `setRiskTolerance`: set the tolerance for risk on the smart vault. must be within prefined bounds.

* `setRiskProvider`: set the address that can set risk on the smart vault.

* `setAllocationProvider`: set the address that can update allocations on the smart vault.

#### `SmartVaultManager.sol`

* `registerSmartVault`: Adds the smart vault to the system.

#### `SpoolAccessControl.sol`

* `grantSmartVaultOwnership`: give ownership of the smart vault to the specified account.

## Role: *Smart Vault Admin*

### Who controls this role?

* The owner of the smart vault is initially granted this role.

 Grants permission to

 * manage rewards on smart vaults,

 * manage roles on smart vaults,

 * redeem for another user of a smart vault.

### What actions can this role take?

#### `SmartVaultManager.sol`

* `redeemFor`: If the the owner has specified it at vault initialization, allows the owner to redeem on behalf of other users.

#### `SpoolAccessControl.sol`

* `grantSmartVaultRole`: allows vault admin to grant roles to other accounts on this smart vault.

* `revokeSmartVaultRole`: allows vault admin to revoke roles for other accounts on this smart vault.

## Role: *Smart Vault Manager*

### Who controls this role?

Marks a contract as a smart vault manager; Is granted to the `SmartVaultManager` contract and the `DepositManager` contract.

### What actions can this role take?

#### `ActionManager.sol`

* `runActions`: execute the predefined set of actions (with given context) on this smart vault.

#### `DepositManager.sol`

* `depositAssets`: during deposit phase, deposit assets to the smart vault.

* `recoverPendingDeposits`: Sends pending deposits on a smart vault to the emergency withdrawal wallet, in the case of an issue with the smart vault.

* `flushSmartVault`: flush smart vault deposits.

* `claimSmartVaultTokens`: during redeem phase, claim user SVTs.

* `syncDeposits`:  during sync phase, ensures SVTs are minted relative to claimed SSTs. 

#### `SmartVault.sol`

* `mintVaultShares`: mints SVTs to account.

* `burnVaultShares`: burns SVTs from account.

* `burnNfts`: burn Deposit/Withdraw NFT(s) from account.

* `claimShares`: transfer SVTs to account.

* `mintDepositNFT`: mint Deposit NFT to account.

* `mintWithdrawalNFT`: mint Deposit NFT to account.

* `transferFromSpender`: transfers SVT's from one account to another.

#### `Strategy.sol`

* `depositFast`: During reallocation phase, deposit funds into this strategy.

* `claimShares`: transfer SSTs from strategy to smart vault.

* `releaseShares`: transfer SSTs from smart vault to strategy.

* `getUsdWorth`: get the value in USD of the assets on the strategy.

* `redeemFast`: withdraw funds, bypassing DHW stage.

#### `StrategyRegistry.sol`

* `removeStrategy`: remove a strategy from the registry.

* `addDeposits`: During flush phase, add the amounts to be deposited to the strategies.

* `addDeposits`: During flush phase, add the amounts to be withdrawn from the strategies.

* `redeemFast`: withdraw funds, bypassing DHW stage.

* `claimWithdrawals`: Claims withdrawals from the strategies.

#### `WithdrawalManager.sol`

* `flushSmartVault`: Flushes smart vaults deposits and withdrawals to the strategies.

* `claimWithdrawal`: after redeem, allows user to claim their withdrawn amount.

* `syncWithdrawals`: Syncs withdrawals between strategies and smart vault after doHardWorks.

* `redeem`: Redeem smart vault shares, to be claimed after the next DHW cycle for this smart vault.

* `redeemFast`: Instantly redeem smart vault shares and claim withdrawn amounts.

## Role: *Guard Allowlist Manager*

### Who controls this role?

Grants permission to manage allowlists with `AllowlistGuard` for a smart vault. `SpoolAdmin` is assigned this role.


### What actions can this role take?

#### `AllowListGuard.sol`

* `addToAllowList`: Add addresses to allowlist for a smart vault.

* `removeFromAllowList`: Remove addresses from allowlist for a smart vault.
 
##  Role: *Master Wallet Manager*

### Who controls this role?

Grants permission to manage assets on master wallet. contracts `DepositManager`, `WithdrawalManager` and `StrategyRegistry` are assigned this role.

### What actions can this role take?

#### `MasterWallet.sol`

* `transfer`: allows caller to transfer amount of token stored on `MasterWallet` contract to recipient.

## Role: *Strategy Registry*

### Who controls this role?

Marks a contract as a strategy registry. Role assigned to the `StrategyRegistry` contract.

### What actions can this role take?

#### `Strategy.sol`

* `redeemFast`: withdraw funds, bypassing DHW stage.

* `redeemShares`: Instantly redeems strategy shares for assets.

* `emergencyWithdraw`: In the case of emergency, instantly withdraws assets, bypassing shares mechanism.

* `doHardWork`: Does hard work: compounds rewards, and deposits/withdraws from the protocol
 
##  Role: *Risk Provider*

### Who controls this role?

Grants permission to act as a risk provider. Should be granted to whoever is allowed to provide risk scores.

### What actions can this role take?

#### `RiskManager.sol`

* `setRiskProvider`: set a risk provider for a smart vault.

* `setRiskScores`: set risk scores for a set of strategies.
 
#### `SpoolLens.sol`

* `getSmartVaultAllocations`: Calculate strategy allocations for a smart vault.
 
## Role: *Allocation Provider*

### Who controls this role?

Grants permission to act as an allocation provider. Should be granted to contracts that are allowed to calculate allocations.

### What actions can this role take?

#### `RiskManager.sol`

* `setAllocationProvider`: Sets an allocation provider for a smart vault.

#### `SpoolLens.sol`

* `getSmartVaultAllocations`: Calculate strategy allocations for a smart vault.

## Role: *Pauser*

### Who controls this role?

Grants permission to pause the system. `SpoolAdmin` is initially assigned this role.

### What actions can this role take?

#### `SpoolAccessControl.sol`

* `pause`: Pauses the whole system.

#### `RewardPool.sol`

* `pause`: Pauses claiming rewards.

## Role: *Unpauser*

### Who controls this role?

Grants permission to unpause the system. `SpoolAdmin` is initially assigned this role.

### What actions can this role take?

#### `SpoolAccessControl.sol`

* `unpause`: Unpauses the whole system.

#### `RewardPool.sol`

* `unpause`: Unpauses claiming rewards.

## Role: *Reward Pool Admin*

### Who controls this role?

Grants permission to manage the rewards payment pool. `SpoolAdmin` is initially assigned this role.

### What actions can this role take?

#### `RewardPool.sol`

* `updateTreeRoot`: Update the existing root for a given cycle.

* `addTreeRoot`: Add a Merkle tree root for a new cycle.

## Role: *Reallocator*

### Who controls this role?

Grants permission to Grants permission to reallocate smart vaults. `SpoolAdmin` is initially assigned this role.

### What actions can this role take?

#### `SmartVaultManager.sol`

* `reallocate`: Reallocates smart vaults; reassigns liquidity between vaults on the basis of risk scores.

## Role: *Strategy*

### Who controls this role?

Grants permission to be used as a strategy. Is assigned to each strategy as it is added to the system. > Note: Generally this role is used as a check on different operations to tell if a strategy has been added to the system or not, rather than explicitly calling actions.

### What actions can this role take?

#### `Swapper.sol`

* `swap`: Performs a swap of tokens with external contracts from a strategy.

## Role: *Strategy Apy Setter*

### Who controls this role?

Grants permission to manually set strategy APY. `SpoolAdmin` is initially assigned this role.

### What actions can this role take?

#### `StrategyRegistry.sol`

* `setStrategyApy`: manually sets the APY for a strategy.

## Role: *Strategy Role Admin*

### Who controls this role?

Grants permission to manage the Strategy role. `StrategyRegistry` is assigned this role.

### What actions can this role take?

#### `SpoolAccessControl.sol`

* `grantRole`: Can grant the Strategy role to an account.

## Role: *Smart Vault Allow Redeem*

### Who controls this role?

Grants permission to vault admins to allow redeem on behalf of other users. The admin for this vault is assigned this role.

### What actions can this role take?

#### `SmartVaultManager.sol`

* `redeemFor`: Allows the owner to redeem on behalf of other users.

## Role: *Smart Vault Allow Redeem Role Admin*

### Who controls this role?

Grants permission to manage the Strategy role. `SmartVaultFactory` is assigned this role.

### What actions can this role take?

#### `SpoolAccessControl.sol`

* `grantRole`: Can grant the Smart Vault Allow Redeem role to an account.

## Role: *Do Hard Worker*

### Who controls this role?

Grants permission to run do hard work. `SpoolAdmin` is initially assigned this role.

### What actions can this role take?

#### `StrategyRegistry.sol`

* `doHardWork`: Does hard work on multiple strategies.

## Role: *Emergency Withdrawal Executor*

### Who controls this role?

Grants permission to immediately withdraw assets in case of emergency. `SpoolAdmin` is initially assigned this role.

### What actions can this role take?

#### `StrategyRegistry.sol`

* `emergencyWithdraw`: Instantly withdraws assets from a strategy, bypassing shares mechanism.
