# Reallocation

## Pre-realloaction

- ideally done right after DHW
- sync vaults involved in reallocation

## Matrix version

Here a matching is done between pairs of strategies. Each smart vault will calculate reallocation and specify
amount of shares to withdraw and how to redistribute them. The strategies then make withdrawals, but these
withdrawals are directed, i.e., withdraw this much from strategy A and deposit into strategy B. If strategy B
has a counter withdrawal to make, this can be matched. Of course the strategy A will merge all its withdrawals
into one actual withdrawal to save gas. The unmatched withdrawals are then redistributed among other strategies
as specified in directed withdrawals. When claiming strategy tokens, smart vaults need to take care to withdraw
appropriate share of both matched value and unmatched deposits.

The challenge here is, that there needs to be an array of all strategies, and a mapping from index of a strategy
on a smart vault to the index of that strategy in the array of all strategies.
