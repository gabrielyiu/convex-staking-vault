// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IBooster {
    /// @dev get pool info
    function poolInfo(uint256 _pid) external view returns(
        address _lptoken, address _token, address _gauge, address _crvRewards, address _stash, bool _shutdown
    );

    /// @dev deposit lp tokens and stake
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns(bool);

    /// @dev withdraw lp tokens
    function withdraw(uint256 _pid, uint256 _amount) external returns(bool);
}
