// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.17;

struct ClaimRequest {
    address smartVault;
    address token;
    uint256 cycle;
    uint256 rewardsTotal;
    bytes32[] proof;
}

error InvalidProof(uint256 idx);
error ProofAlreadyClaimed(uint256 idx);
error RootUpdatesNotAllowed();
error InvalidCycle();

interface IRewardPool {
    /**
     * @notice Claim smart vault incentives by submitting a Merkle proof
     */
    function claim(ClaimRequest[] calldata data) external;

    /**
     * @notice Add a Merkle tree root for a new cycle
     * @param root Root to add
     */
    function addTreeRoot(bytes32 root) external;

    /**
     * @notice Update existing root for a given cycle
     * @param root New root
     * @param cycle Cycle to update
     */
    function updateTreeRoot(bytes32 root, uint256 cycle) external;

    /**
     * @notice Verify a Merkle proof for given claim request
     */
    function verify(ClaimRequest calldata data, address user) external view returns (bool);

    /**
     * @notice Return Merkle tree root for given cycle
     */
    function roots(uint256 cycle) external view returns (bytes32);

    /**
     * @notice Return true if leaf has already been claimed
     */
    function isLeafClaimed(bytes32 leaf) external view returns (bool);

    /**
     * @notice Current cycle count
     */
    function cycleCount() external view returns (uint256);

    /**
     * @notice Whether pool allows updating existing Merkle tree roots
     */
    function allowUpdates() external view returns (bool);

    /**
     * @notice Pause claiming
     */
    function pause() external;

    /**
     * @notice Unapuse claiming
     */
    function unpause() external;

    /**
     * @notice Amount already claimed by user per token per vault
     * @param user claimer
     * @param smartVault smart vault address
     * @param token token address
     */
    function rewardsClaimed(address user, address smartVault, address token) external view returns (uint256);

    /**
     * @notice New root was added to the pool
     * @param cycle Number of new cycle
     * @param root Newly added root
     */
    event PoolRootAdded(uint256 indexed cycle, bytes32 root);

    /**
     * @notice Pool's root was updated
     * @param cycle Number of cycle that was updated
     * @param previousRoot Previous root for the cycle
     * @param newRoot New root for the cycle
     */
    event PoolRootUpdated(uint256 indexed cycle, bytes32 previousRoot, bytes32 newRoot);

    event RewardsClaimed(
        address indexed user, address indexed smartVault, address indexed token, uint256 cycle, uint256 amount
    );
}
