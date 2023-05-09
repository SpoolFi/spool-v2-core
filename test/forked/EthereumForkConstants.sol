// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

uint256 constant MAINNET_FORK_BLOCK = 16_683_900;

// tokens
address constant USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
address constant USDT = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
address constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

address constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

address constant COMP = address(0xc00e94Cb662C3520282E6f5717214004A7f26888);
address constant NOTE = address(0xCFEAead4947f0705A14ec42aC3D44129E1Ef3eD5);
address constant stkAAVE = address(0x4da27a545c0c5B758a6BA100e3a049001de870f5);

// Aave V2
address constant AAVE_V2_LENDING_POOL_ADDRESSES_PROVIDER = address(0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5);
address constant aUSDC = address(0xBcca60bB61934080951369a648Fb03DF4F96263C);

// Compound V2
address constant COMPTROLLER = address(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
address constant cUSDC = address(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
address constant cDAI = address(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);

// Morpho
//   Compound V2
address constant MORPHO_COMPOUND_V2 = address(0x8888882f8f843896699869179fB6E4f7e3B58888);
address constant MORPHO_COMPOUND_V2_LENS = address(0x930f1b46e1D081Ec1524efD95752bE3eCe51EF67);
//   AAVE V2
address constant MORPHO_AAVE_V2 = address(0x777777c9898D384F785Ee44Acfe945efDFf5f3E0);
address constant MORPHO_AAVE_V2_LENS = address(0x507fA343d0A90786d86C7cd885f5C49263A91FF4);

// Curve
address constant CRV_TOKEN = address(0xD533a949740bb3306d119CC777fa900bA034cd52);

//   3pool
address constant CURVE_3POOL_POOL = address(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
address constant CURVE_3POOL_LP_TOKEN = address(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
address constant CURVE_3POOL_GAUGE = address(0xbFcF63294aD7105dEa65aA58F8AE5BE2D9d0952A);
//   alusd
address constant CURVE_ALUSD_POOL_TOKEN = address(0x43b4FdFD4Ff969587185cDB6f0BD875c5Fc83f8c);
address constant CURVE_ALUSD_GAUGE = address(0x9582C4ADACB3BCE56Fea3e590F05c3ca2fb9C477);
//   frxeth
address constant CURVE_FRXETH_POOL = address(0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577);
//   steth
address constant CURVE_STETH_POOL = address(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

// Convex
address constant CONVEX_BOOSTER = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

//   DAI+USDC+USDT - 3pool
uint96 constant CONVEX_3POOL_PID = 9;
//   alUSD+3Crv - alusd
uint96 constant CONVEX_ALUSD_PID = 36;

// Idle
address constant IDLE_BEST_YIELD_SENIOR_USDC = address(0x5274891bEC421B39D23760c04A6755eCB444797C);

// Yearn v2
address constant YEARN_V2_USDC_TOKEN_VAULT = address(0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE);

// Notional Finance
address constant NOTIONAL_FINANCE_PROXY = address(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
address constant NOTIONAL_FINANCE_NUSDC = address(0x18b0Fc5A233acF1586Da7C199Ca9E3f486305A29);

// Lido
address constant LIDO = address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

// Frax
address constant FRXETH_TOKEN = address(0x5E8422345238F34275888049021821E8E08CAa1f);
address constant SFRXETH_TOKEN = address(0xac3E018457B222d93114458476f3E3416Abbe38F);
address constant FRXETH_MINTER = address(0xbAFA44EFE7901E04E39Dad13167D089C559c1138);

// Rocket Pool
address constant ROCKET_SWAP_ROUTER = address(0x16D5A408e807db8eF7c578279BEeEe6b228f1c1C);
