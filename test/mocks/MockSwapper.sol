pragma solidity ^0.8.0;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract MockSwapper {
    IERC20 tokenA;
    IERC20 tokenB;
    uint256 exchangeRate;

    constructor(IERC20 tokenA_, IERC20 tokenB_, uint256 exchangeRate_) {
        tokenA = tokenA_;
        tokenB = tokenB_;
        exchangeRate = exchangeRate_;
    }

    function swap(address token, uint256 amount) external returns (uint256) {
        uint256 out = 0;
        IERC20 source;
        IERC20 target;

        if (address(token) == address(tokenA)) {
            source = tokenA;
            target = tokenB;
            out = amount * exchangeRate / 10 ** 18;
        } else if (address(token) == address(tokenB)) {
            source = tokenB;
            target = tokenA;
            out = amount * 10 ** 18 / exchangeRate;
        } else {
            revert("Invalid token");
        }

        source.transferFrom(msg.sender, address(this), amount);
        target.transferFrom(address(this), msg.sender, out);

        return out;
    }
}
