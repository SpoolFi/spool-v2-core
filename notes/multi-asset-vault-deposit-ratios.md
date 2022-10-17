# On calculation of multi-asset deposit ratio

Deposits into multi-asset vault need to be done in appropriate ratios between all deposited assets. This ratio depends on vault's set allocation between different strategies, and the ratio required by each of the strategy. And when flushing deposits into strategies, deposited funds need to be divided back accordingly.

## Example vault

Lets say we have a vault with three strategies, Aave, Idle and Yearn, with following allocation set between them, 60%, 30% and 10% respectively. The vault is a multi-asset vault with deposits made in ETH and BTC. A user wants to make a deposit, valued at 1,000,000 USD. The question is now how much ETH and BTC they need to deposit.

| allocation | Aave | Idle | Yearn |
| ---------- | ---- | ---- | ----- |
|            |  60% |  30% |   10% |


The allocation between strategies is split in deposit value in USD. This means that 600,000 USD worth of the deposit should go to Aave, 300,000 USD worth to Idle and 100,000 USD worth to Yearn.

Each strategy has a required ratio in which deposits need to be made in, for Aave this is 0.068 BTC per ETH, for Idle it is 0.067 BTC per ETH and for Yearn 0.069 BTC per ETH. Lets say that current exchange rates are 1336.61 USD/ETH and 19730.31 USD/BTC. The vault ratios can now be expressed in dollars as following: for Aave 1331.61 USD worth of ETH for 1341.66 USD worth of BTC, for Idle 1336.61 versus 1321.93 and for Yearn 1336.61 versus 1361.39.

|     ratio |  Aave |  Idle | Yearn |
| --------- | ----- | ----- | ----- |
| ETH [ETH] |     1 |     1 |     1 |
| BTC [BTC] | 0.068 | 0.067 | 0.069 |

|     ratio |    Aave |    Idle |   Yearn |
| --------- | ------- | ------- | ------- |
| ETH [USD] | 1336.61 | 1336.61 | 1336.61 |
| BTC [USD] | 1341.66 | 1321.93 | 1361.39 |

This ratios determine split between the deposit into a strategy between ETH and USD. Using the USD allocations, the ratios between ETH and BTC, and the USD exchange rates, it can be calculated that Aave needs a deposit of 224.03 ETH and 15.23 BTC, Idle of 112.84 ETH and 7.56 BTC, and Yearn of 37.06 ETH and 2.56 BTC.

|   deposit |   Aave |   Idle | Yearn |
| --------- | ------ | ------ | ----- |
| ETH [ETH] | 224.03 | 112.84 | 37.06 |
| BTC [BTC] |  15.23 |   7.56 |  2.56 |

Which gives the final ratio for the deposit into the vault of 373.93 ETH and 25.35 BTC, or normalizing this to 0.0678 BTC for every ETH.

## Formula for calculating vault's deposit ratio

Using the following nomenclature

|    sign |                                               meaning |
| ------- | ----------------------------------------------------- |
|     $s$ | strategy, e.g., Aave, Idle, Yearn                     |
|     $a$ | asset, e.g., ETH, BTC                                 |
|   $e_a$ | exchange rate between asset $a$ and USD               |
|   $A_s$ | vault's allocation for strategy $s$                   |
| $r_a^s$ | required deposit ratio for asset $a$ and strategy $s$ |
|   $R_a$ | vault's required deposit ratio for asset $a$          |

and the above process, the following formula can be derived:

$$ R_a = \sum_s A_s \cdot \frac {r_a^s} {\sum_{a'} r_{a'}^s \cdot e_{a'}} $$

Connecting back to the example, this formula says that for every $R_{ETH}$ of ETH deposited into the vault, there needs to be $R_{BTC}$ of BTC deposited as well.

To reduce the deposit costs, this ratio can be calculated once per vault flush and be used for the whole flush duration. This could be done on the vault flush itself or alternatively on first deposit.

## Example deposit

Lets say that deposits were made to the above vault in the following amounts: 100 ETH and 6.78 BTC, which is in the correct ratio. This amount needs to be divided among the strategies in a way that fulfills vault's allocation between strategies and each strategies' required ratio between assets. First, USD value of deposits can be calculated: 133661 USD worth of ETH and 1337663.26 USD worth of BTC, for the total of 267427.26 USD.

| deposit |  asset |        USD |
| ------- | ------ | ---------- |
|     ETH | 100.00 |  133661.00 |
|     BTC |   6.78 | 1337663.26 |

This USD value should be allocated between the strategies according to vault's allocation, 160456.26 USD to Aave, 80228.18 USD to Idle and 26742.72 USD to Yearn. Then these values can be divided among the assets according to each strategy's required ratio.

| deposit share |     Aave |     Idle |    Yearn |
| ------------- | -------- | -------- | -------- |
|           USD | 16458.26 | 80228.18 | 26742.72 |

| deposit share | Aave  | Idle  | Yearn |
| ------------- | ----- | ----- | ----- |
|           ETH | 59.91 | 30.18 | 9.91  |
|           BTC | 4.07  | 2.02  | 0.68  |

## Formula for dividing deposit among strategies

Using the same nomenclature as above with following additions

|    sign |                                             meaning |
| ------- | --------------------------------------------------- |
|   $D_a$ | amount of asset $a$ deposited into vault            |
| $N_a^s$ | amount of asset $a$ to be flushed into strategy $s$ |

and the above process, the following formula can be derived:

$$ N_a^s = \left( \sum_{a'} D_{a'} \cdot e_{a'} \right) \cdot A_s \cdot \frac {r_a^s} {\sum_{a'} r_{a'}^s \cdot e_{a'}} $$

where $\sum_a D_a \cdot e_a$ represents the total USD value of the deposit and can be calculated once, and second part is the same as in the calculation of vault's deposit ratio.
