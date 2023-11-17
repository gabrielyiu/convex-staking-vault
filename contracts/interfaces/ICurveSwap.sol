// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ICurveSwap {
    function get_virtual_price() external view returns (uint256);
    function coins(uint256) external view returns (address);

    function add_liquidity(
        uint256[3] calldata amounts,
        uint256 min_mint_amount
    ) external;

    function remove_liquidity(
        uint256 amount,
        uint256[3] calldata min_mint_amounts
    ) external;

    function claimable_tokens(address) external view returns (uint256);    
    function claimable_rewards(address,address) external view returns (uint256);
}
