// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {Ownable} from "openzeppelin/access/Ownable.sol";

abstract contract IYieldSource is Ownable {
    function yieldToken() external view virtual returns (IERC20);

    function sourceToken() external view virtual returns (IERC20);

    function pendingYield() external view virtual returns (uint256);

    function pendingYieldInToken(
        address outToken
    ) external view virtual returns (uint256);

    function totalDeposit() external view virtual returns (uint256);

    function deposit(uint256 amount) external virtual;

    function withdraw(uint256 amount, bool claim, address to) external virtual;

    function claimAndConvert(
        address outToken,
        uint256 amount,
        uint256 amountOutMin
    ) external virtual returns (uint256, uint256);

    error AddressZero();
    error AmountZero();
}
