# Non-atomic DHW

## Specification

### Overview

Strategies in the Spool ecosystem are wrappers that allow the core contracts to interact with external protocols in a unified way. Main interactions are depositing in and withdrawing from these external protocols, along with claiming rewards and others. Current DHW system is assuming that all the interactions with external protocols are atomic and can be executed within the same transaction as DHW is run. However, some potential candidates for integration do not follow our assumptions. So, a non-atomic DHW is needed to support such protocols.

### External protocol limitations

- deposit limit
    - limited amount that can be deposited at once
    - large deposits should be split into chunks
- non-atomic deposits
    - deposits are not instant
    - should first request deposit and then confirm that deposit succeeded / claim underlying tokens
    - this also affects compounded rewards!
- withdrawal limit
    - limited amount that can be withdrawn at once
    - high slippage incurred for large withdrawals
    - large withdrawals should be split into chunks
- non-atomic withdrawals
    - withdrawals are not instant
    - should first request withdrawal and then confirm that withdrawal succeeded / claim underlying assets

### Restrictions

- general restrictions
    - reallocation
        - not really possible, since it should be atomic
    - redeem fast
        - if non-atomic withdrawal, redeem fast is not possible
    - redeem strategy shares
        - if non-atomic withdrawals, async redeem flow must be used
- restrictions while strategy's DHW is in progress
    - new DHW cannot start
    - redeem fast cannot be executed
    - smart vault cannot be synced until DHW is finished

### Flows

#### Smart vault flush cycle

- deposits / withdrawals made to the smart vault
- smart vault is flushed
    - check that DHWs for previous flush cycle are finished
    - check that last DHWs are finished (?)
- DHW is triggered for the strategies
- DHW is finished for the strategies
- smart vault is synced
    - check that DHWs for synced indexes are finished
- deposits / withdrawals are claimed

#### Redeem strategy shares - overview

sync version (current flow):

- can be used if strategy supports atomic withdrawal
- execute redeem strategy shares
    - check that strategy's DHW is not already in progress

async version:

- should be used if strategy has non-atomic withdrawal
- async version of redeem strategy shares is initiated
    - check that strategy's DHW is not already in progress (?)
- DHW is triggered for the strategy
- DHW is finished for the strategy
- redeemed assets are claimed

#### Redeem strategy shares - smart contracts

sync version:

- mostly same flow as now
- check that last DHW is finished
- check that redeemal finished / is possible atomically

async version:

- execute redeem strategy shares async
    - check that last DHW is finished (?)
    - mint 'NFT' for withdrawer
    - add withdrawn shares to next DHW
- wait for DHW to complete
- claim withdrawn assets
    - check that last DHW is finished
    - burn 'NFT'
    - claim withdrawn assets similar to how smart vaults do it on sync

#### Redeem fast - smart contracts

- mostly same flow as now
- check that last DHW is finished
- check that redeemal finished / is possible atomically

#### DHW flow - keeper network

initial DHW:

- trigger node finds strategies to DHW
- trigger node sends a dhw event to the keeper nodes
- primary keeper node proposes DHW parameters
- secondary keeper nodes validate and sign DHW parameters
- executor keeper node executes DHW

while some strategy's DHW is in progress:

- trigger node finds strategies that can continue DHW
- trigger node sends a dhw-continuation event to the keeper nodes
- primary keeper node proposes DHW-continuation parameters
- secondary keeper nodes validate and sign DHW continuation parameters
- executor keeper node executes DHW continuation

#### DHW flow - smart contracts

initial DHW:

- mostly same as currently
- check that previous DHWs are finished
- execute DHW for each strategy
    - as much as possible with protocol restrictions
    - notify DHW status
- update bookkeeping
    - along with DHW status

DHW continuation:

- new flow
- check that last DHWs are in progress
- continue DHW per strategy
    - as much as possible with protocol restrictions and previous state
    - perform before checks (?)
    - continue compound if needed
    - collect platform fees if needed
    - do matching if needed
        - matching should only be done once, after compounding
    - continue deposit / withdrawal if needed
    - mint shares / gather withdrawn assets if needed
    - notify DHW status
- update bookkeeping
    - along with DHW status

### Smart contract design guidelines

- strategies should notify the strategy registry of the DHW status
    - on DHW execution and DHW continuation
    - options
        - store state on strategy
            - strategies should be updated
            - all other state is stored on strategy registry
            - strategy registry could duplicate state
        - via returned value
            - strategies should be updated to add to the return state
            - or implement custom decoding of returned value to account for non-atomic / atomic strategies
        - via callback
            - if no callback, it should default to finished
            - no need to update all the strategies
            - might need multiple callbacks to support also redeem fast and redeem strategy shares
- strategies should notify the strategy registry of the withdrawal status
    - on redeem fast and redeem strategy shares
        - see above for options
- DHW status storage
    - it would be great if we do not have to push status for all current strategies
    - think about values to use for DHW status to lower gas costs
    - maybe use
        - `FINISHED => 1` and `IN_PROGRESS => 2`
        - with checks `isFinished => status < 2` and `isInProgress => status == 2`
- it will probably be needed to implement a non-atomic strategy base
    - to cover early exits from DHW and DHW continuation
    - can we push some DHW logic into a shared library to lower contract size of the strategies
- investigate whether a flag is needed to signal that a strategy is non-atomic
    - can this be done without upgrading existing strategies (?)
        - maybe this point is moot due to other points
- implement mock strategies for non-atomic protocols for testing new and updated flows
    - should cover different protocol limitations
    - this will also help us see possible design patterns for such real strategies

### Open questions

- Do we need to wait until last DHWs are finished before a smart vault can be flushed? Or can flush happen into the next DHW index while DHW is still in progress?
- Do we need to wait until last DHWs are finished before redeem strategy shares async flow can be initiated? Or can it happen into the next DHW index while DHW is still in progress?
- Do we need to perform before checks on continuation DHWs? They are mostly there to prevent front-running DHW with flushing attacker's smart vault. So from that perspective they are only needed on initial DHW, since deposited amounts and redeemed shares are frozen from there until the DHW finishes. Is there any other use currently?

## Scope

### Solidity

- introduce a DHW status
    - `FINISHED` and `IN_PROGRESS`
    - strategy should notify the state
        - either extend returned value (upgrade strategies unless custom decoding)
        - or callback to strategy registry
        - or store on strategy (upgrade strategies)
- limit actions when strategy is non-atomic
    - redeem fast (if non-atomic withdrawal)
    - redeem strategy shares (if non-atomic withdrawal), use async flow
    - smart vault reallocation
- limit actions when DHW status is `IN_PROGRESS`
    - DHW
    - redeem fast
    - smart vault sync
    - redeem strategy shares
- introduce method to continue DHW
    - only if strategy is in progress
    - make one of the input parameters a bytes array
        - to cover a wide variety of possible continuation modes
    - can execute multiple strategies at once
- introduce method for non-atomic redeem strategy shares
    - in case strategy cannot withdraw from protocol atomically
    - idea
        - push SSTs to the DHW
        - note withdrawal (mint wNFT on strategy?)
        - SSTs would be redeemed same as SSTs from smart vault withdrawal
        - add way to claim the withdrawn amount
- maybe a different base strategy for non-atomic strategies
    - flag that strategy is non-atomic
        - we will probably need to distinguish between atomic and non-atomic strategies

### Subgraph

- add support for DHW status
- maybe add support for marking non-atomic strategies (if available on-chain)
- add support for new events
    - DHW continuation
    - non-atomic redeem strategy shares

### Parameter gatherer

- support gathering of parameters for DHW continuation

### Keeper network

- support automatic continuation of DHW
    - trigger should check if any continuation is needed
        - should not adhere to DHW schedule
        - emit dhw-continuation event
    - keeper nodes should gather parameters and execute
        - when receive dhw-continuation event
        - same consensus rules as for DHW (1 propose, 2 verify and sign, then execute)

### Backend services / SDK

- is strategy is non-atomic
- is any strategy in vault non-atomic
- is DHW for any strategy in vault in progress
- support for non-atomic redeem strategy shares (?)

### Frontend

- mark smart vaults with non-atomic strategies
- disable fast withdrawal if not possible
- display further info on limitation of non-atomic strategies

## Notes

### Strategy

- doHardWork
    - plenty of work to do here
- redeemFast
    - used for fast redeeming of shares by SVT holders
        - not possible when non-atomic-withdrawal strategies are present
    - should be disabled for non-atomic withdrawals
- redeemShares
    - used for redeeming shares by direct SST holders
        - designed async flow for this
    - should be disabled for non-atomic withdrawals
- depositFast
    - used in reallocation
        - no reallocation when non-atomic strategies are used
    - should be disabled for non-atomic deposits

## Flow overview

### Smart vault manager

- `flushSmartVault`
    - vault needs to be synced
        - all DHWs need to pass
        - no new restrictions
    - in principle, all DHW indexes need to be incremented
        - all DHWs need to be initiated
- `reallocate`
    - DHWs should just be run
    - not possible for non-atomic operations
        - block if non-atomic strategies used
        - could try if only atomic operations are present (like if strategy has atomic deposit and non-atomic withdrawal)
- `removeStrategyFromVaults`
    - anytime
- `syncSmartVault`
    - all DHWs need to pass
    - no new restrictions
- `redeemFast`
    - not possible if non-atomic withdrawal
        - block if non-atomic strategies used
        - could try if only atomic operations are present (like if strategy has non-atomic deposit and atomic withdrawal)
    - TODO: if trying, should we wait until DHWs have passed?
- `claimWithdrawal`
    - vault needs to be synced
    - no new restrictions
- `claimSmartVaultTokens`
    - vault needs to be synced
    - no new restrictions
- `redeem`
    - no restrictions
- `redeemFor`
    - no restrictions
- `deposit`
    - no restrictions
- `recoverPendingDeposits`
    - all strategies must be ghost strategies
    - no new restrictions

### Strategy registry

- `removeStrategy`
    - system call; ROLE_SMART_VAULT_MANAGER
- `setEcosystemFee`
    - no new restrictions
    - TODO: check
- `setTreasuryFee`
    - no new restrictions
    - TODO: check
- `doHardWork`
    - previous DHW needs to be finished
- `doHardWorkContinue`
    - current DHW needs to be in progress
- `addDeposits`
    - system call; ROLE_SMART_VAULT_MANAGER
- `addWithdrawals`
    - system call; ROLE_SMART_VAULT_MANAGER
- `redeemFast`
    - system call; ROLE_SMART_VAULT_MANAGER
- `claimWithdrawals`
    - system call; ROLE_SMART_VAULT_MANAGER
- `redeemStrategyShares`
    - not possible if non-atomic withdrawal
        - block if non-atomic strategies used
        - could try if only atomic operations are present (like if strategy has non-atomic deposit and atomic withdrawal)
    - TODO: if trying, should we wait until DHW has passed?
- `redeemStrategySharesAsync`
    - no restrictions
- `claimStrategyShareWithdrawals`
    - DHWs for `redeemStrategySharesAsync` need to finish
    - no other restrictions
- `emergencyWithdraw`
    - depending on the protocol

### Strategy

- `beforeDepositCheck`
    - system call
- `beforeRedeemalCheck`
    - system call
- `doHardWork`
    - system call; ROLE_STRATEGY_REGISTRY
- `doHardWorkContinue`
    - system call; ROLE_STRATEGY_REGISTRY
- `claimShares`
    - system call; ROLE_SMART_VAULT_MANAGER
- `releaseShares`
    - system call; ROLE_SMART_VAULT_MANAGER, ROLE_STRATEGY_REGISTRY
- `redeemFast`
    - system call; ROLE_SMART_VAULT_MANAGER, ROLE_STRATEGY_REGISTRY
- `redeemShares`
    - system call; ROLE_STRATEGY_REGISTRY
- `depositFast`
    - system call; ROLE_SMART_VAULT_MANAGER
- `emergencyWithdraw`
    - system call; ROLE_STRATEGY_REGISTRY
- `getUsdWorth`
    - system call; ROLE_SMART_VAULT_MANAGER
- `getProtocolRewards`
    - system call; view execution

### Overview

- smart vault manager
    - vault flush
        - not possible until previous flush is synced
        - could be modified
            - to allow flush once all DHWs start for previous flush
    - vault sync
        - not possible until all DHWs pass
    - reallocation
        - needs DHW executed just before reallocation
        - not possible when vault has non-atomic strategies
        - alternative
            - try to execute it
            - check if all actions are atomic
            - not possible when strategy has DHW in progress
    - redeem fast
        - is possible if strategy has atomic withdrawal
        - not possible when strategy has DHW in progress
        - alternative
            - not possible when vault has non-atomic strategies
- strategy registry
    - setEcosystemFee, setTreasuryFee
        - are possible whenever
        - have to check if calculation OK if fees change during DHW
    - DWH
        - not possible while previous DHW in progress
        - should execute DHW continuation instead
    - DHW continuation
        - not possible if previous DHW is finished
        - continuation not even needed
    - redeem strategy shares
        - is same as redeem fast
        - is possible if strategy has atomic withdrawal
        - not possible when strategy has DHW in progress
        - alternative
            - not possible for non-atomic strategies
    - redeem strategy shares async
        - is possible whenever
        - should be used when strategy has non-atomic withdrawals
        - can be used on all strategies
        - taps into DHW flow
        - caller should call claim strategy share withdrawals after DHW has passed
