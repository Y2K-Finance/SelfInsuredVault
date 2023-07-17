// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {IUniswapV2Router02} from "uniswap-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {IYieldSource} from "../interfaces/IYieldSource.sol";
import {IRewardTracker} from "../interfaces/gmx/IRewardTracker.sol";
import {IRewardRouterV2} from "../interfaces/gmx/IRewardRouterV2.sol";

/// @title Yield Source contract for Staked GLP
/// @author Y2K Finance
/// @dev This is for reward management by LP staking, not yield bearing asset
///      Owner of this contract is always SIV
contract StakedGLPYieldSource is IYieldSource {
    using SafeERC20 for IERC20;

    /// @notice Fee + Staked GLP token
    IERC20 public immutable override sourceToken;

    /// @notice Output token: WETH
    IERC20 public immutable override yieldToken;

    /// @notice GMX Reward Router
    IRewardRouterV2 public immutable rewardRouter;

    /// @notice Swap router
    IUniswapV2Router02 public swapRouter;

    /**
     * @notice Contract constructor
     * @param _sGLP Fee + Staked GLP
     * @param _weth WETH token
     * @param _rewardRouter Reward router contract
     * @param _swapRouter Swap router contract
     */
    constructor(
        address _sGLP,
        address _weth,
        address _rewardRouter,
        address _swapRouter
    ) {
        if (_sGLP == address(0)) revert AddressZero();
        if (_weth == address(0)) revert AddressZero();
        if (_rewardRouter == address(0)) revert AddressZero();
        if (_swapRouter == address(0)) revert AddressZero();

        sourceToken = IERC20(_sGLP);
        yieldToken = IERC20(_weth);
        rewardRouter = IRewardRouterV2(_rewardRouter);
        swapRouter = IUniswapV2Router02(_swapRouter);
    }

    /**
     * @notice Total deposited lp token
     */
    function totalDeposit() external view override returns (uint256) {
        return sourceToken.balanceOf(address(this));
    }

    /**
     * @notice Returns pending yield
     */
    function pendingYield() public view override returns (uint256) {
        // WETH rewards
        IRewardTracker feeGlpTracker = IRewardTracker(
            rewardRouter.feeGlpTracker()
        );
        IRewardTracker feeGmxTracker = IRewardTracker(
            rewardRouter.feeGmxTracker()
        );
        return
            feeGlpTracker.claimable(address(this)) +
            feeGmxTracker.claimable(address(this)) +
            yieldToken.balanceOf(address(this));
    }

    /**
     * @notice Returns expected token from yield
     */
    function pendingYieldInToken(
        address outToken
    ) public view override returns (uint256 amountOut) {
        uint256 amountIn = pendingYield();
        if (outToken == address(yieldToken)) {
            return amountIn;
        }
        if (amountIn > 0) {
            address[] memory path = new address[](2);
            path[0] = address(yieldToken);
            path[1] = outToken;
            uint256[] memory amounts = swapRouter.getAmountsOut(amountIn, path);
            amountOut = amounts[1];
        }
    }

    /**
     * @notice Stake sGLP tokens
     */
    function deposit(uint256 amount) external override onlyOwner {
        if (amount == 0) revert AmountZero();
        sourceToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
     * @notice Withdraw lp tokens
     */
    function withdraw(
        uint256 amount,
        bool claim,
        address to
    ) external override onlyOwner {
        if (amount == 0) revert AmountZero();
        if (to == address(0)) revert AddressZero();

        if (claim) _harvest();

        uint256 balance = sourceToken.balanceOf(address(this));
        if (amount > balance) {
            amount = balance;
        }
        sourceToken.safeTransfer(to, amount);
    }

    /**
     * @notice Claim rewards and convert
     */
    function claimAndConvert(
        address outToken,
        uint256 amount,
        uint256 amountOutMin
    )
        external
        override
        onlyOwner
        returns (uint256 yieldAmount, uint256 actualOut)
    {
        if (outToken == address(0)) revert AddressZero();
        if (amount == 0) revert AmountZero();

        // harvest by withdraw
        _harvest();

        uint256 balance = yieldToken.balanceOf(address(this));
        // if available reward in reward tracker is not enough
        if (amount > balance) {
            amount = balance;
        }

        if (outToken == address(yieldToken)) {
            yieldToken.transfer(msg.sender, amount);
            actualOut = amount;
        } else {
            // swap yield into outToken
            yieldToken.safeApprove(address(swapRouter), amount);
            address[] memory path = new address[](2);
            path[0] = address(yieldToken);
            path[1] = outToken;
            uint256[] memory amounts = swapRouter.swapExactTokensForTokens(
                amount,
                amountOutMin,
                path,
                msg.sender,
                block.timestamp
            );
            actualOut = amounts[1];
        }

        yieldAmount = _transferYield();
    }

    /**
     * @notice Harvest rewards
     */
    function _harvest() private returns (uint256 amount) {
        uint256 before = yieldToken.balanceOf(address(this));
        rewardRouter.claimFees();
        amount = yieldToken.balanceOf(address(this)) - before;
        rewardRouter.compound();
    }

    /**
     * @notice Transfer all yield tokens to vault
     */
    function _transferYield() internal returns (uint256 amount) {
        amount = yieldToken.balanceOf(address(this));
        yieldToken.safeTransfer(msg.sender, amount);
    }
}
