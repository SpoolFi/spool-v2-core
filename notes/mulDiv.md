# mulDiv

## multipliers

- USD price oracle
- strategy / smart vault initial shares multiplier
- smart vault deposits precision multiplier

### USD price oracle

- tokens decimals: up to 18
- price feed decimals: 8 (except for Ampleforth one with 18)
- USD value decimals: need 18 + 8 = 26 for full precision
- allows for USD value up to 10e12 or $1T

Can go with lower precision:

- for cent-wei accuracy: 18 + 2 = 20
    - at price $0.01 per token, 1 wei still contributes something to total
- for dollar-wei accuracy: 18 + 0 = 18
    - at price $1 per token, 1 wei still contributes something to total

### initial shares multiplier

- sstsToMint
    - on first deposit: usdWorthDeposited * INITIAL_SHARE_MULTIPLIER
    - on subsequent deposits: usdWorthDeposited * totalSupply() / usdWorthBeforeDeposit
- first deposit:
    - usdWorthDeposited decimals: 26
    - INITIAL_SHARE_MULTIPLIER decimals: 30
    - SSTs decimals: 56 (!)
- subsequent deposits
    - totalSupply decimals: 56
    - usdWorthDeposited decimals: 26
    - usdWorthBeforeDeposit decimals: 26

The INITIAL_SHARE_MULTIPLIER value was set arbitrarily to 10e30 value. Lets analyze this a bit. The multiplier is directly used on the first deposit, but its effect matters for subsequent deposits. To calculate the amount of SSTs to mint on deposit, one compares the current supply of tokens, with deposit worth and previous strategy worth:

$$ sstsToMint = totalSupplyBefore \cdot \frac {usdWorthDeposited} {usdWorthBefore} $$

where the totalSupply is related to the INITIAL_SHARE_MULTIPLIER.

What matters here is not the absolute value of the usdWorthDeposited and usdWorthBefore, but their ratio. Lets imagine a strategy with \$1B usdWorthBefore and a deposit of \$0.01. In order for that \$0.01 to produce any shares, the totalSupply needs to have at least 9 + 2 = 11 decimal places. This means that also INITIAL_SHARE_MULTIPLIER could be set to 10e11, instead of 10e30.

However, the totalSupply is proportional to the INITIAL_SHARE_MULTIPLIER and to usdWorthBefore (ignoring yield), where the usdWorth is measured in USD price oracle decimals, which means that it already passes the 11 decimals threshold mentioned above.

The INITIAL_SHARE_MULTIPLIER should be set such that the expected amount of tokens does not exceed 2^128 or about 10e38. So if we imagine a strategy with cumulative \$1B of deposits (i.e., 10e9), then we have:

$$ INITIAL\_SHARE\_MULTIPLIER decimals <= 38 - 9 - USD value decimals $$

which gives

- 3 decimals for full precision of USD value
- 9 decimals for cent-wei accuracy
- 11 decimals for dollar-wei accuracy

This will give about 29 decimals worth of tokens for each deposited USD.

> **Note:** very similar analysis also applies to smart vaults.


---

price: 18
strategy max value: $10T

10T => 10 * 1e12 => 1e13

38 - 13 - 18 = 7
7 - 4 = 3
