# Fees

## Smart vault fees

### Management fees

On smart vault creation, the owner can specify the amount of management fees they would like to collect. Maximal amount is limited to $5\%$ annually.

The management fees are collected based on amount of assets locked in the vault and are not connected to the yield generated by the strategies.

How we implemented this is that management fees are collected on every sync of the smart vault. Each sync we take a percent of fees proportional to the time elapsed since the last sync.

This method is not exact, in the sense that over the year, not exactly $F_{year}$ fees will be taken, but slightly less. We can estimate the discrepancy between fees actually collected and the ones specified by the smart vault's owner.

Lets assume that the amount of assets locked in the smart vault does not change over the year, and that the smart vault will be synced in exact time periods. We will use the following nomenclature:

- $f$: management fees in percent as specified by the smart vault owner
- $N$: number of syncs that are performed per year
- $V$: user value locked in the smart vault

On each sync we take $F/N$ fees from the $V$

$$ V' = V \cdot \left(1 - \frac{f}{N}\right) $$

After all $N$ collections, the user value locked in the smart vault is

$$ V' = V \cdot \left(1 - \frac{f}{N} \right)^N $$

with the amount of fees collected being

$$ F_N = V - V' = V \cdot \left( 1 - \left( 1 - \frac{f}{N} \right)^N \right) $$

Now lets estimate how much fees are collected, if the management fee is set to $3\%$ and the vault is synced every two days, i.e., $N=180$:

$$ F^{3\%}_{180} = V \cdot 0.0296 $$

which means that instead of $3\%$ fees we collected $2.96\%$ fees.

The worst case scenario is when the management fee is set to $5\%$ (maximal amount) and the fees are taken continuously, i.e., $N \rightarrow \infty$

In that case we can rewrite the expression for $F_N$ as

$$ N_{N \rightarrow \infty} = V \cdot \left( 1 - e^{-f} \right) $$

So now the worst case becomes

$$ N^{5\%}_{\infty} = V \cdot 0.0488 $$

which means that instead of $5\%$ fees we collected $4.88\%$ fees.
