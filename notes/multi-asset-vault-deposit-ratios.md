# On calculation of multi-asset deposit ratio

Deposits into multi-asset vault need to be done in appropriate ratios between all deposited assets. This ratio depends on vault's set allocation between different strategies, and the ratio required by each of the strategy. And when flushing deposits into strategies, deposited funds need to be divided back accordingly.

See also the accompanying spreadsheet with interactive calculations that follow the below procedures.

## Calculation of ideal deposit ratio

First lets have a look into how to calculate the ideal deposit ratio, based on vault's set allocation between the strategies, the asset ratios demanded by the strategies, and the exchange rate between assets (or rather between assets and USD).

### Example vault

Lets say we have a vault with three strategies, Aave, Idle and Yearn, with the following allocation set between them:

|            | Aave | Idle | Yearn |
| ---------- | ---- | ---- | ----- |
| allocation |  60% |  30% |   10% |

meaning that 60% of the deposit's value should be deposited in the Aave strategy. The vault is a multi-asset vault with deposits made in ETH, BTC, and BNB, with the following exchange rate:

|     |     ETH |      BTC |    BNB |
| --- | ------- | -------- | ------ |
| USD | 1208.16 | 16404.71 | 270.39 |

where 1 ETH costs $1206.16. Each strategy also has a required ratio between the assets for depositing into it:

|     |  Aave |  Idle | Yearn |
| --- | ----- | ----- | ----- |
| ETH |     1 |     1 |     1 |
| BTC | 0.071 | 0.074 | 0.076 |
| BNB |   4.3 |   4.5 |   4.6 |

In the case of Aave, the deposit need 0.071 BTC and 4.3 of BNB tokens for each ETH token deposited.

### Derivation

A user wants to make a deposit, valued at $1,000,000. The question is now how much ETH, BTC, and BNB they need to deposit.

First lets split this amount between the strategies based on vault's allocation:

|               |    Aave |    Idle |   Yearn |
| ------------- | ------- | ------- | ------- |
| deposit share | 600,000 | 300,000 | 100,000 |

Then we can express the ratios between assets required by the strategies in $ by multiplying them with the exchange rates:

|         |    Aave |    Idle |   Yearn |
| ------- | ------- | ------- | ------- |
| ETH [$] | 1208.16 | 1208.16 | 1208.16 |
| BTC [$] | 1164.73 | 1213.95 | 1246.76 |
| BNB [$] | 1162.68 | 1216.76 | 1243.79 |

From this we can calculate normalization factor per strategy by summing values for all assets:

|               |    Aave |    Idle |   Yearn |
| ------------- | ------- | ------- | ------- |
| normalization | 3535.57 | 3638.86 | 3698.71 |

Now we can split the $ amount allocated for each strategy among the assets by multiplying it with $ ratio and dividing by the normalization:

|         |       Aave |       Idle |     Yearn |
| ------- | ---------- | ---------- | --------- |
| ETH [$] | 205,029.38 |  99,604.72 | 32,664.34 |
| BTC [$] | 197,659.89 | 100,081.95 | 33,707.90 |
| BNB [$] | 197,310.74 | 100,313.32 | 33,627.76 |

This means that of the $600,000 of the deposit allocated to the Aave, $205,029.38 worth should be deposited in ETH. To get the number of tokens for each asset, we divide the $ values by the corresponding exchange rate:

|     |   Aave |   Idle |  Yearn |
| --- | ------ | ------ | ------ |
| ETH | 169.70 |  82.44 |  27.04 |
| BTC |  12.05 |   6.10 |   2.05 |
| BNB | 729.73 | 370.99 | 124.37 |

From this we can get the full deposit amount by summing over the strategies:

|        |    ETH |   BTC |     BNB |
| ------ | ------ | ----- | ------- |
| tokens | 279.18 | 20.20 | 1225.09 |

So the deposit of $1,000,000 should consist of 279.18 ETH, 20.20 BTC, and 1225.09 BNB.

### Formula for calculating vault's ideal deposit ratio

Using the following nomenclature

|    sign |                                                      meaning |
| ------- | ------------------------------------------------------------ |
|     $s$ | strategy, e.g., Aave, Idle, Yearn                            |
|     $a$ | asset, e.g., ETH, BTC                                        |
|   $e_a$ | exchange rate between asset $a$ and USD                      |
|   $A_s$ | vault's allocation for strategy $s$                          |
| $r_a^s$ | required deposit ratio for asset $a$ and strategy $s$        |
| $R_a^s$ | vault's ideal division factor for asset $a$ and strategy $s$ |
|   $R_a$ | vault's ideal deposit ratio for asset $a$                    |

and the above process, we can derive the following two formulas:

$$ R_a^s = A_s \cdot \frac {r_a^s} {\sum_{a'} r_{a'}^s \cdot e_{a'}} $$
$$ R_a = \sum_s R_a^s $$

The second formula expresses the ideal ratio in which the deposits should be made. Connecting to the above example, for each $R_{ETH}$ of ETH deposited into the vault, there needs to be $R_{BTC}$ of BTC and $R_{BNB}$ of BNB deposited as well.

The first formula then tells, how this deposit should be distributed among the strategies.

## Dividing the deposit among the strategies

The deposit user makes into the vault is not instantly routed to the underlying strategies, but is a multi-step process designed to lower the deposit costs, and to allow for fair distribution of yield. The process works in so called flush cycles:

- user deposits are gathered on the vault level
- at some point the gathered deposits are flushed to the strategy levels, starting new flush cycle
- each strategy performs a DHW on its own cycle, routing the gathered assets to the underlying protocol

There are a few things to note here:

- all deposits to a vault made in the same flush-cycle, need to adhere to the same ratio between the assets
- this ratio is calculated based on exchange rates and strategy ratios at the last flush time
- the exchange rates and strategy ratios can change during the flush cycle

The exchange rate and strategy ratios that are the basis for deposit ratio calculation can change during the flush cycle. This means that generally, the actual deposit ratio does not match the ideal one at the time of the vault flush. So we can not simply use the above formula to divide the deposit among the strategies.

The following subsections present a few alternative schemes for how to divide the deposit among the strategies.

To help follow along the schemes, we take the example vault as described [here](#example-vault) with the following actual and ideal deposit:

|        |    ETH |  BTC |    BNB |
| ------ | ------ | ---- | ------ |
|  ideal | 100.00 | 7.23 | 438.81 |
| actual | 100.00 | 7.00 | 420.00 |

### Swap to ideal ratio

One option is to swap the tokens in such a way to achieve the ideal ratio. However, everyone should be able to trigger the flush for a smart vault, not just the system. Now the question becomes on who can set the slippage for the swapping. If the user can set the slippage they can make a profit from this. If it is the system, there would need to be additional components that increase the complexity of the system and the maintenance of it.

So, according to the example we would have to swap (ignoring slippage) 0.31 BTC for 18.81 BNB tokens.

### Swap-less scheme 1: Divide based on ideal flush division

Even though the deposit is not made in the ideal deposit ratio, we can try to divide it according to the ideal flush division.

This has a nice property that imbalance of tokens affects all strategies the same relative amount. However, the flush division does not follow the vault's strategy allocation, which breaks the exposure promised to the user.

This scheme also has two alternative derivations, ending up with the same result.

#### Alternative: scale ideal

Here we first calculate the $ value of the deposit using the exchange rates. Now we can calculate the ideal number of tokens for each strategy following the procedure described in [Derivation section](#derivation).

Then we calculate the difference between the ideal amount of tokens and the actual amount of tokens. From this we can find the scaling factor for each asset that would bring the ideal asset amount in line with actual amount.

We then apply this factor back to the ideal flush division.

#### Alternative: idealize remainder

In this alternative we also calculate the $ value of the deposit using the exchange rates, calculate the ideal number of tokens for each strategy following the procedure described in [Derivation section](#derivation), and calculate the difference between the ideal and actual amount of tokens.

In contrast to the first alternative, we don't calculate the scaling factor, but divide the remainder by the ideal flush division, as we did with the whole deposit in the [main scheme](#swap-less-scheme-1-divide-based-on-ideal-flush-division).

Then we add both to yield the final flush division.

### Swap-less scheme 2: Allocate remainder

Here we again start with calculating the $ value of the deposit using the exchange rates, then calculating the ideal number of tokens for each strategy following the procedure described in [Derivation section](#derivation), and calculating the difference between the ideal and actual amount of tokens.

Then we divide remainder of the assets among the strategies based on vault's allocation.

Adding the ideal part and the remainder, gives us the final flush division.

This has a nice property of following the vault's allocation. However, since the remainder of the tokens can be negative, it can happen in certain scenarios, that the final division includes a negative contribution to the strategy for an asset. While this can be corrected for, it would complicate the logic quite a bit.

### Swap-less scheme 3: Maximal ideal plus allocate remainder

This scheme is a sort of combination of the [swap-less scheme 1](#swap-less-scheme-1-divide-based-on-ideal-flush-division) and [swap-less scheme 2](#swap-less-scheme-2-allocate-remainder).

Here we start by identifying the asset with relatively smallest share in the deposit, compared to the ideal deposit ratio. Then we calculate the ideal amount of other assets based on the smallest one. Since these assets are in the ideal ratio, we can divide them according to the ideal flush division as in [swap-less scheme 1](#swap-less-scheme-1-divide-based-on-ideal-flush-division).

Now we can calculate the remainder of the tokens and divide them among the strategies based on vault's allocation similar to the [swap-less scheme 2](#swap-less-scheme-2-allocate-remainder). In contrast to that scheme, the remainder of the assets cannot be negative, since the ideal division was made on the subset of the deposited tokens.

So this scheme also ends up following the vault's allocation and is viable in all conditions. However, opposed to the [swap-less scheme 1](#swap-less-scheme-1-divide-based-on-ideal-flush-division), the division affect certain strategies more than others.
