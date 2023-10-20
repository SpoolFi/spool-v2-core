# LSD yield

## reth-holding strategy

This is a liquid staking derivative strategy where eth is staked with Rocket pool to be used for spinning up validators. Users staking share is represented by rETH. The value of rETH compared to eth is growing with validation rewards collected by validators spinned up using the staked eth. The strategy uses the Rocket swap router to buy and sell rETH for eth.

To get the base yield for this strategy we are tracking the exchange rate between ETH and rETH as given by the rETH token contract. Specifically, we are getting the exchange rate by calling the `rEthToken.getEthValue(1 ether)` which gives us the value of 1 rETH token in ETH. To get the yield we compare the change of this exchange rate between last and current DHW:

```
yieldPercentage = (currentValue - previousValue) * YIELD_FULL_PERCENT / previousValue
```

where `currentValue` and `previousValue` are current and previous values of the exchange rate and `YIELD_FULL_PERCENT` is internal precision used for yield calculations.

There are no reward tokens, which means there is no compound yield.

The address of the rEthToken is `0xae78736Cd615f374D3085123A210448E74Fc6393`.

## sfrxeth-holding strategy

This is a liquid staking derivative strategy where eth is staked with Frax to be used for spinning up validators. Frax has two tokens, frxETH and sfrxETH. The frxETH token is minted 1:1 when submiting eth to Frax. It cannot be redeemed back for eth and just holding it is not enough to be eligible for staking yield. The sfrxETH token is minted when depositing frxETH. The price of sfrxETH compared to frxETH is increasing over time based on rewards accrued by validators.

To get the base yield for this strategy we are tracking the exchange rate between frxETH and sfrxETH as given by the sfrxETH token contract. Specifically, we are getting the exchange rate by calling the `sfrxEthToken.convertToAssets(1 ether)` which gives us the value of 1 sfrxETH token in frxETH tokens (which has same value as ETH). To get the yield we compare the change of this exchange rate between last and current DHW, using same formula as for reth-holding strategy.

There are no reward tokens, which means there is no compound yield.

The address of the sfrxEthToken is `0xac3E018457B222d93114458476f3E3416Abbe38F`.

## steth-holding strategy

This is a liquid staking derivative strategy where eth is staked with Lido to be used for spinning up validators. Users staking share is represented by stETH that is minted 1:1 when staking eth.

The stETH is a rebasing token, meaning that the amount of stETH in your wallet is increasing. Internally this is tracked by amount of shares in stETH you own.

To get the base yield of this strategy we are tracking the exchange rate between shares and stETH (or ETH) as given by the lido contract. Specifically, we are getting the exchange rate by calling the `lido.getPooledEthByShares(1 ether)` which gives us the value of 1 ether of shares in stETH tokens (which has same value as ETH). To get the yield we compare the change of this exchange rate between last and current DHW, using same formula as for reth-holding strategy.

There are no reward tokens, which means there is no compound yield.

The address of the lido is `0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84`.
