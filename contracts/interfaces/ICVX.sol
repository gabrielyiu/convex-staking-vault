// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICVX is IERC20 {
    function reductionPerCliff() external view returns (uint);

    function totalCliffs() external view returns (uint);

    function maxSupply() external view returns (uint);
}
