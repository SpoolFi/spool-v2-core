// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@solmate/tokens/WETH.sol";
import "forge-std/Script.sol";

contract DeployTokens is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("TOKEN_DEPLOYER");
        vm.startBroadcast(deployerPrivateKey);

        ERC20Mintable dai = new ERC20Mintable("DAI", "DAI", 18);
        ERC20Mintable usdc = new ERC20Mintable("USDC", "USDC", 6);
        ERC20Mintable usdt = new ERC20Mintable("USDT", "USDT", 6);
        WETH weth = new WETH();

        console.log(address(dai));
        console.log(address(usdc));
        console.log(address(usdt));
        console.log(address(weth));
    }
}

contract ERC20Mintable is ERC20 {
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_, decimals_) {}

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, amount);
    }
}
