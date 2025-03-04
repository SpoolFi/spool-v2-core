// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

uint256 constant MAINNET_FORK_BLOCK = 16_683_900;
uint256 constant MAINNET_FORK_BLOCK_EXTENDED_0 = 18_776_000;
uint256 constant MAINNET_FORK_BLOCK_EXTENDED_1 = 18_963_715;
uint256 constant MAINNET_FORK_BLOCK_EXTENDED_2 = 19_610_823;
uint256 constant MAINNET_FORK_BLOCK_EXTENDED_3 = 19_781_440;
uint256 constant MAINNET_FORK_BLOCK_EXTENDED_4 = 19_982_746;
uint256 constant MAINNET_FORK_BLOCK_EXTENDED_5 = 20_583_563;
uint256 constant MAINNET_FORK_BLOCK_EXTENDED_6 = 21_192_351;

// whales
address constant USDC_WHALE = address(0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf);

// tokens
address constant USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
address constant USDT = address(0xdAC17F958D2ee523a2206206994597C13D831ec7);
address constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
address constant WBTC = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);

address constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

address constant AAVE = address(0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9);
address constant COMP = address(0xc00e94Cb662C3520282E6f5717214004A7f26888);
address constant NOTE = address(0xCFEAead4947f0705A14ec42aC3D44129E1Ef3eD5);
address constant stkAAVE = address(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
address constant GHO = address(0x40D16FC0246aD3160Ccc09B8D0D3A2cD28aE6C2f);

// Aave
address constant STAKED_GHO = address(0x1a88Df1cFe15Af22B3c4c783D4e6F7F9e0C1885d);

//   V2
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
//   oeth
address constant CURVE_OETH_POOL = address(0x94B17476A93b3262d87B9a326965D1E91f9c13E7);
//   steth-frxeth
address constant CURVE_STFRXETH_POOL = address(0x4d9f9D15101EEC665F77210cB999639f760F831E);

// Convex
address constant CONVEX_BOOSTER = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

//   DAI+USDC+USDT - 3pool
uint96 constant CONVEX_3POOL_PID = 9;
//   alUSD+3Crv - alusd
uint96 constant CONVEX_ALUSD_PID = 36;
//   stETH+frxETH - st-frxETH
uint96 constant CONVEX_STFRXETH_PID = 161;

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

// Origin
address constant OETH_TOKEN = address(0x856c4Efb76C1D1AE02e20CEB03A2A6a08b0b8dC3);
address constant OETH_VAULT = address(0x39254033945AA2E4809Cc2977E7087BEE48bd7Ab);

// Gearbox V3
address constant SDWETH_TOKEN = address(0x0418fEB7d0B25C411EB77cD654305d29FcbFf685);
address constant SDUSDC_TOKEN = address(0x9ef444a6d7F4A5adcd68FD5329aA5240C90E14d2);
address constant SDDAI_TOKEN = address(0xC853E4DA38d9Bd1d01675355b8c8f3BBC1451973);
address constant SDUSDT_TOKEN = address(0x16adAb68bDEcE3089D4f1626Bb5AEDD0d02471aD);
address constant SDCRVUSD_TOKEN = address(0xfBCA378AeA93EADD6882299A3d74D8641Cc0C4BC);
address constant SDGHO_TOKEN = address(0xE2037090f896A858E3168B978668F22026AC52e7);
address constant SDWBTC_TOKEN = address(0xA8cE662E45E825DAF178DA2c8d5Fae97696A788A);

// Metamorpho
address constant METAMORPHO_RE7_USDT = address(0x95EeF579155cd2C5510F312c8fA39208c3Be01a8);
address constant METAMORPHO_RE7_WBTC = address(0xE0C98605f279e4D7946d25B75869c69802823763);

// Yearn V3
address constant YEARN_AJNA_DAI_VAULT = 0xe24BA27551aBE96Ca401D39761cA2319Ea14e3CB; // yvAjnaDAI
address constant YEARN_AJNA_DAI_HARVESTER = 0x082a5743aAdf3d0Daf750EeF24652b36a68B1e9C; // ysyvAjnaDAI

address constant YEARN_USDC_VAULT = 0xBe53A109B494E5c9f97b9Cd39Fe969BE68BF6204;
address constant YEARN_USDC_GAUGE = 0x622fA41799406B120f9a40dA843D358b7b2CFEE3;

// Ethena
address constant USDe_TOKEN = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
address constant sUSDe_TOKEN = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
address constant ENA_TOKEN = 0x57e114B691Db790C35207b2e685D4A43181e6061;
address constant ETHENA_REWARD_DISTRIBUTOR_WALLET = 0xe3880B792F6F0f8795CbAACd92E7Ca78F5d3646e;
address constant ETHENA_REWARD_DISTRIBUTOR_CONTRACT = 0xf2fa332bD83149c66b09B45670bCe64746C6b439;

// Dinero
address constant PIREXETH = 0xD664b74274DfEB538d9baC494F3a4760828B02b0;
