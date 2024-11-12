// Mock strategy for testnet. WILL NOT BE USED IN PRODUCTION.
// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "src/interfaces/Constants.sol";

interface IERC20Mintable is IERC20 {
    function mint(address, uint256) external;
}

/* @dev Simple staking protocol, targetting a yearly yield, for testnet purposes.
 * Uses MasterChef algorithm to distribute rewards amongst users, with APY target based on total deposits.
 */
contract MockProtocol is Ownable {
    using SafeERC20 for IERC20;

    // ************ STRUCTS ************
    struct User {
        uint256 shares; // How many tokens the user has staked
        uint256 debt; // Reward debt
    }

    // ************ VARIABLES ************
    // The token to stake and earn.
    IERC20Mintable public token;
    // APY in basis points. max is FULL_PERCENT.
    uint256 public apy;
    // Last time contract minted tokens.
    uint256 public updated;
    // shares of each user that stakes tokens.
    mapping(address => User) public users;
    // Total shares across all users.
    uint256 public shares;
    // Accumulated rewards per single share. scaled up for accuracy.
    uint256 public accumulator;
    // Scale for reward accumulation.
    uint256 public constant scale = 1e12;

    // ************ EVENTS ************
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    // ************ CONSTRUCTOR ************
    constructor(address _token, uint256 _apy) {
        token = IERC20Mintable(_token);
        apy = _apy;
        updated = block.timestamp;
    }

    // ************ EXTERNAL MUTATIVE FUNCTIONS ************
    function deposit(uint256 _amount) external updater {
        User storage user = users[msg.sender];

        user.shares += _amount;
        user.debt = debtFor(user.shares, accumulator);
        shares += _amount;

        token.transferFrom(address(msg.sender), address(this), _amount);

        emit Deposit(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external updater {
        User storage user = users[msg.sender];
        require(_amount > 0 && _amount <= user.shares, "withdraw: not good");

        user.shares -= _amount;
        user.debt = debtFor(user.shares, accumulator);
        shares -= _amount;

        token.transfer(msg.sender, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    function updateAPY(uint256 _apy) external updater onlyOwner {
        require(_apy <= FULL_PERCENT, "updateAPY: too high");
        apy = _apy;
    }

    // ************ INTERNAL MUTATIVE FUNCTIONS ************
    function update(address user) internal {
        (uint256 _accumulator, uint256 _reward, uint256 _debt, uint256 _earned) = _update(user);

        accumulator = _accumulator;
        updated = block.timestamp;
        users[user].debt = _debt;
        token.mint(address(this), _reward);
        token.transfer(msg.sender, _earned);
    }

    // ************ VIEW FUNCTIONS ************
    function _update(address _user)
        internal
        view
        returns (uint256 _accumulator, uint256 _reward, uint256 _debt, uint256 _earned)
    {
        User storage user = users[_user];

        _reward = rewards();
        _accumulator = (shares == 0) ? accumulator : accumulator + ((_reward * scale) / shares);
        _debt = debtFor(user.shares, _accumulator);
        _earned = _debt - user.debt;
    }

    function debtFor(uint256 amount, uint256 _accumulator) public pure returns (uint256) {
        return (amount * _accumulator) / scale;
    }

    function rewards() public view returns (uint256) {
        if (block.timestamp == updated) return 0;
        uint256 multiplier = block.timestamp - updated;
        uint256 yearlyReward = (shares * apy) / FULL_PERCENT;
        return (yearlyReward * multiplier) / 52 weeks;
    }

    function balanceOf(address user) public view returns (uint256 balance) {
        (,,, uint256 _earned) = _update(user);

        return users[user].shares + _earned;
    }

    // ************ MODIFIERS ************
    modifier updater() {
        update(msg.sender);
        _;
    }
}
