// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.16;

struct ClaimRequest {
    address smartVault;
    address token;
    uint256 cycle;
    uint256 amount;
    bytes32[] proof;
}

error InvalidProof(uint256 idx);
error ProofAlreadyClaimed(uint256 idx);

interface IRewardPool {
    /**
     * @notice Claim smart vault incentives by submitting a Merkle proof
     */
    function claim(ClaimRequest[] calldata data) external;

    /**
     * @notice Add a Merkle tree root
     */
    function addTreeRoot(bytes32 root) external;

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
    function leafsClaimed(bytes32 leaf) external view returns (bool);

    /**
     * @notice Current cycle count
     */
    function cycleCount() external view returns (uint256);

    event PoolCycleIncreased(uint256 cycle);
}
