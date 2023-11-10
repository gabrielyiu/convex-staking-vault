// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IBaseRewardPool {
    /// @dev get balance of an address
    function balanceOf(address _account) external returns(uint256);
    /// @dev withdraw to a convex tokenized deposit
    function withdraw(uint256 _amount, bool _claim) external returns(bool);
    /// @dev withdraw directly to curve LP token
    function withdrawAndUnwrap(uint256 _amount, bool _claim) external returns(bool);
    /// @dev claim rewards
    function getReward() external returns(bool);
    /// @dev stake a convex tokenized deposit
    function stake(uint256 _amount) external returns(bool);
    /// @dev stake a convex tokenized deposit for another address(transfering ownership)
    function stakeFor(address _account,uint256 _amount) external returns(bool);

    /// @dev get earned rewards
    function earned(address account) external view returns (uint256);
    function rewardPerToken() external view returns (uint256);
    function lastTimeRewardApplicable() external view returns (uint256);
}
