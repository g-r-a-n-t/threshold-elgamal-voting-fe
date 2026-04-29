// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IThresholdElection {
    function castVote(uint256 c1_x, uint256 c1_y, uint256 c2_x, uint256 c2_y) external;

    function getAggregate() external view returns (uint256 c1_x, uint256 c1_y, uint256 c2_x, uint256 c2_y);

    function closeVoting() external;

    function recordFinalResult(int256 tally, uint256 m_x, uint256 m_y) external;
}

