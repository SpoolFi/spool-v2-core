// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

import "@openzeppelin/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/security/Pausable.sol";
import "../interfaces/IRewardPool.sol";
import "../access/SpoolAccessControllable.sol";

contract RewardPool is IRewardPool, Pausable {
    using SafeERC20 for IERC20;

    mapping(uint256 => bytes32) public roots;

    mapping(bytes32 => bool) public isLeafClaimed;

    mapping(address => mapping(address => mapping(address => uint256))) public rewardsClaimed;

    uint256 public cycleCount;

    bool public immutable allowUpdates;

    /**
     * @dev Spool access control manager.
     */
    ISpoolAccessControl internal immutable _accessControl;

    constructor(ISpoolAccessControl accessControl, bool allowUpdates_) {
        allowUpdates = allowUpdates_;
        _accessControl = accessControl;
    }

    function pause() external onlyRole(ROLE_PAUSER, msg.sender) {
        _pause();
    }

    function unpause() external onlyRole(ROLE_UNPAUSER, msg.sender) {
        _unpause();
    }

    function addTreeRoot(bytes32 root) external onlyRole(ROLE_REWARD_POOL_ADMIN, msg.sender) {
        cycleCount++;
        roots[cycleCount] = root;

        emit PoolRootAdded(cycleCount);
    }

    function updateTreeRoot(bytes32 root, uint256 cycle) external onlyRole(ROLE_REWARD_POOL_ADMIN, msg.sender) {
        if (!allowUpdates) {
            revert RootUpdatesNotAllowed();
        }

        if (cycle > cycleCount) {
            revert InvalidCycle();
        }

        roots[cycle] = root;

        emit PoolRootUpdated(cycle);
    }

    function claim(ClaimRequest[] calldata data) public whenNotPaused {
        for (uint256 i; i < data.length; ++i) {
            bytes32 leaf = _getLeaf(data[i], msg.sender);
            if (isLeafClaimed[leaf]) {
                revert ProofAlreadyClaimed(i);
            }

            if (!_verify(data[i], leaf)) {
                revert InvalidProof(i);
            }

            isLeafClaimed[leaf] = true;

            uint256 alreadyClaimed = rewardsClaimed[msg.sender][data[i].smartVault][data[i].token];
            uint256 toClaim = data[i].rewardsTotal - alreadyClaimed;
            rewardsClaimed[msg.sender][data[i].smartVault][data[i].token] += toClaim;

            IERC20(data[i].token).safeTransfer(msg.sender, toClaim);

            emit RewardsClaimed(msg.sender, data[i].smartVault, data[i].token, data[i].cycle, toClaim);
        }
    }

    function verify(ClaimRequest memory data, address user) public view returns (bool) {
        return _verify(data, _getLeaf(data, user));
    }

    function _verify(ClaimRequest memory data, bytes32 leaf) internal view returns (bool) {
        return MerkleProof.verify(data.proof, roots[data.cycle], leaf);
    }

    function _getLeaf(ClaimRequest memory data, address user) internal pure returns (bytes32) {
        return keccak256(
            bytes.concat(keccak256(abi.encode(user, data.cycle, data.smartVault, data.token, data.rewardsTotal)))
        );
    }

    /**
     * @dev Throws if the contract or the whole system is paused.
     */
    function _requireNotPaused() internal view override {
        if (_accessControl.paused()) {
            revert SystemPaused();
        }

        super._requireNotPaused();
    }

    /**
     * @dev Reverts if an account is missing a role.\
     * @param role Role to check for.
     * @param account Account to check.
     */
    function _checkRole(bytes32 role, address account) internal view virtual {
        if (!_accessControl.hasRole(role, account)) {
            revert MissingRole(role, account);
        }
    }

    /**
     * @notice Only allows accounts with granted role.
     * @dev Reverts when the account fails check.
     * @param role Role to check for.
     * @param account Account to check.
     */
    modifier onlyRole(bytes32 role, address account) {
        _checkRole(role, account);
        _;
    }

    /**
     * @notice Only allows accounts that are Spool admins or admins of a smart vault.
     * @dev Reverts when the account fails check.
     * @param smartVault Address of the smart vault.
     * @param account Account to check.
     */
    modifier onlyAdminOrVaultAdmin(address smartVault, address account) {
        _accessControl.checkIsAdminOrVaultAdmin(smartVault, account);
        _;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}
