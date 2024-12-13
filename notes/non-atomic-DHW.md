# Non-atomic DHW

Strategies in the Spool ecosystem are wrappers that allow the core contracts to interact with external protocols in a unified way. Main interactions are depositing in and withdrawing from these external protocols, along with claiming rewards and others. Current DHW system is assuming that all the interactions with external protocols are atomic and can be executed within the same transaction as DHW is run. However, some potential candidates for integration do not follow our assumptions. So, a non-atomic DHW is needed to support such protocols.

## Limitations of external protocols

- deposit limit
    - limited amount that can be deposited at once
    - large deposits should be split into chunks
- non-atomic deposits
    - deposits are not instant
    - should first request deposit and then confirm that deposit succeeded / claim underlying tokens
    - this also affects compounded rewards
- withdrawal limit
    - limited amount that can be withdrawn at once
    - high slippage incurred for large withdrawals
    - large withdrawals should be split into chunks
- non-atomic withdrawals
    - withdrawals are not instant
    - should first request withdrawal and then confirm that withdrawal succeeded / claim underlying assets

> **Note:** some strategies can in principle be non-atomic, but at some / most times act as atomic.

## Flows

### Smart vault flush cycle

- deposits / withdrawals are made to the smart vault
- smart vault is flushed
- DHW is triggered for the strategies
- DHW is finished
- smart vault is synced
- deposits / withdrawals can be claimed

### Redeem strategy shares

sync version (current flow):

- can be used with strategies that support atomic withdrawal
    - optimistically execute, revert if non-atomic
- strategy must be idle
- execute redeem strategy shares
    - withdrawal is immediately executed and assets transferred

async version (new flow):

- can be used with all strategies
    - should be used with strategies that do not support atomic withdrawal
- async redeem strategy shares is initiated
- DHW is triggered for the strategy
- DHW is finished for the strategy
- withdrawals can be claimed

### Redeem fast

- can be used with strategies that support atomic withdrawal
    - optimistically execute, revert if non-atomic
- strategy must be idle
- execute redeem fast
    - withdrawal is immediately executed and assets transferred

> **Note:** users cannot redeem fast from a smart vault if it contains any strategy with non-atomic withdrawal.

### DHW

- keeper network triggers DHW on-chain
    - during DHW time
    - find idle strategies that need DHW
    - gather parameters
    - trigger DHW on-chain
- while there are unfinished DHWs
    - keeper network triggers DHW continuation on-chain
        - periodically
        - find strategies with unfinished DHW that need continuing at the time
        - gather parametes
        - trigger DHW continuation on-chain

> **Note:** different non-atomic strategies require different downtimes between DHW and DHW continuation. The keeper network should figure out for each such strategy when it should be trigger DHW continuation.
> **Note:** a strategy might need multiple DHW continuations.

### Reallocation

- can be done if smart vault has strategies with correct combination of atomic operations
    - e.g., strategy has atomic deposits and non-atomic withdrawal
        - if reallocation would deposit into the strategy, it would reallocate
        - if reallocation would withdraw from the strategy, it would revert
    - optimistically execute, revert if non-atomic
- strategies must be idle
- execute reallocation
    - reallocation is immediately executed

> **Note:** cannot reallocate a smart vault if any of its strategies would trigger a non-atomic interaction with underlying protocol.

## Implementation details

### Smart contracts

- introduce an atomicity classification for the strategies
    - `0` -> atomic strategy
    - `1` -> strategy with non-atomic deposit
    - `2` -> strategy with non-atomic withdrawal
    - `3` -> non-atomic strategy
    - set on strategy registration
    - compatible with already registered strategies
        - no need to backfill
    - bitwise operations can be used to check for specifics
- introduce a strategy status
    - `1` -> idle strategy
    - `2` -> strategy with a DHW in-progress
    - avoid `0` as a value to avoid high gas cost of setting storage from `0` to a non-`0` value
    - allows for extension of the strategy status
        - e.g., to allow for pausing of the strategy
- DHW
    - initial DHW
        - can only be executed when strategy is idle
        - strategies must report back whether the DHW has finished
            - **breaking change**, we will need to upgrade the strategies
    - introduce a DHW continuation method
        - can only be called when strategy has a DHW in-progress
        - in principle, a strategy can require multiple continuations to finish the DHW
- introduce async method to redeem strategy shares
    - uses DHW mechanism to redeem strategy shares
        - acts similar to a withdrawal requested by one of the smart vaults
    - no NFTs or similar are issued
    - to claim assets, user must provide the DHW index of the strategy at which they initiated the withdrawal
        - this is not very ergonomic, but this will probably only be done by the fee recipient
- introduce a non-atomic strategy base
    - `StrategyNonAtomic`
    - support both atomic and non-atomic deposited and withdrawals in all combinations
        - e.g., atomic deposit and non-atomic withdrawal
    - supports a case where interactions can sometime be atomic and sometime non-atomic
    - restrictions
        - the interactions must be either fully atomic or fully non-atomic
            - can fully resolve on DHW or fully resolve on continuation
            - can not partially resolve on DHW and partially resolve on continuation
                - e.g., half of withdrawal is processed immediately and half of withdrawal is processed later
        - all interactions must finish within one DHW continuation
            - does not support multiple DHW continuations
        -> cannot be used to do multiple swaps through a pool with low liquidity
    - fairness
        - withdrawers do not get their share of compound yield, but they do get their share of base yield
        - no fees are taken on any yield generated by withdrawn withdrawal from initial DHW to DHW completion
        - no fees are taken on any yield generated by deposited deposits from initial DHW to DHW completion
        - fees are taken according to the portion of yield each user is entitled to
    - other
        - executes a single deposit or withdrawal
            - matching is done on deposit + compound vs withdrawals
        - no compounding is done on DHW continuation
        - base yield is taken into account on DHW continuation

> **Note:** additional non-atomic strategy bases can be created to cover specific needs.
> E.g. 1, a strategy base for strategies with atomic deposit and non-atomic withdrawals, which could do the compounding in a separate step. This would simplify the calculations and allow withdrawers to receive the compound yield.
> E.g. 2, a strategy base for strategies that need more then one DHW continuation to finish the DHW.
