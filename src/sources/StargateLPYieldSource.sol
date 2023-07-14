// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {IUniswapV2Router02} from "uniswap-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import {IYieldSource} from "../interfaces/IYieldSource.sol";
import {ILPStaking} from "../interfaces/stargate/ILPStaking.sol";

/// @title Yield Source contract for stargate LP
/// @author Y2K Finance
/// @dev This is for reward management by LP staking, not yield bearing asset
///      Owner of this contract is always SIV
contract StargateLPYieldSource is IYieldSource {
    using SafeERC20 for IERC20;

    /// @notice LP token
    IERC20 public immutable override sourceToken;

    /// @notice Reward token = STG token
    IERC20 public immutable override yieldToken;

    /// @notice LP staking contract
    ILPStaking public immutable staking;

    /// @notice Uniswap router
    IUniswapV2Router02 public router;

    /// @notice Pool Id
    uint256 public pid;

    /**
     * @notice Contract constructor
     * @param _pid Staking pool id
     * @param _lpToken LP token
     * @param _staking Staking contract
     * @param _router Router for swap
     */
    constructor(
        uint256 _pid,
        address _lpToken,
        address _staking,
        address _router
    ) {
        if (_lpToken == address(0)) revert AddressZero();
        if (_staking == address(0)) revert AddressZero();
        if (_router == address(0)) revert AddressZero();

        pid = _pid;
        staking = ILPStaking(_staking);
        sourceToken = IERC20(_lpToken);
        router = IUniswapV2Router02(_router);
        yieldToken = IERC20(staking.stargate());
    }

    /**
     * @notice Returns pending STG yield
     */
    function pendingYield() public view override returns (uint256) {
        uint256 balance = yieldToken.balanceOf(address(this));
        return balance + staking.pendingStargate(pid, address(this));
    }

    /**
     * @notice Returns expected token from yield
     */
    function pendingYieldInToken(
        address outToken
    ) external view override returns (uint256 amountOut) {
        uint256 amountIn = pendingYield();
        if (amountIn > 0) {
            address[] memory path = new address[](2);
            path[0] = address(yieldToken);
            path[1] = outToken;
            uint256[] memory amounts = router.getAmountsOut(amountIn, path);
            amountOut = amounts[1];
        }
    }

    /**
     * @notice Total deposited lp token
     */
    function totalDeposit() external view override returns (uint256) {
        return _totalDeposit();
    }

    /**
     * @notice Stake lp tokens
     */
    function deposit(uint256 amount) external override onlyOwner {
        if (amount == 0) revert AmountZero();

        sourceToken.safeTransferFrom(msg.sender, address(this), amount);
        _deposit(amount);
    }

    /**
     * @notice Withdraw lp tokens
     * @dev Harvest happens automatically by stargate
     */
    function withdraw(
        uint256 amount,
        bool claim,
        address to
    ) external override onlyOwner {
        if (amount == 0) revert AmountZero();
        if (to == address(0)) revert AddressZero();

        staking.withdraw(pid, amount);
        uint256 balance = sourceToken.balanceOf(address(this));
        if (amount > balance) {
            amount = balance;
        }
        sourceToken.safeTransfer(to, amount);
        if (!claim) {
            _deposit(amount);
        }
    }

    /**
     * @notice Harvest rewards
     */
    function claimAndConvert(
        address outToken,
        uint256 amount
    )
        external
        override
        onlyOwner
        returns (uint256 yieldAmount, uint256 actualOut)
    {
        if (outToken == address(0)) revert AddressZero();
        if (amount == 0) revert AmountZero();

        // harvest by withdraw
        ILPStaking.UserInfo memory info = staking.userInfo(pid, address(this));

        // NOTE: This withdrawas from the staking contract
        staking.withdraw(pid, info.amount);

        // redeposit asset
        // NOTE: This deposits into the staking contract (assuming this is Stargate)? Why would we be depositing back into it?
        _deposit(info.amount);

        // swap yield into outToken
        yieldToken.safeApprove(address(router), amount);
        address[] memory path = new address[](2);
        path[0] = address(yieldToken);
        path[1] = outToken;
        // TODO: This could be front-run if the minOut is zero - change amountOutMin to a value
        // NOTE: You need to make it ->  amount * multiple / slippage where slippage is either a fixed value or a provided input on selfInsuredVault call
        // NOTE: If it's fixed there is a risk of reverting! So providing slippage would be better
        uint256[] memory amounts = router.swapExactTokensForTokens(
            amount,
            0,
            path,
            msg.sender,
            block.timestamp
        );
        actualOut = amounts[1];

        // transfer rest yield
        // NOTE: Why is the yield token being transferred to the msg.sender? Shouldn't it be swapped or something?
        yieldAmount = _transferYield();
    }

    /**
     * @notice Total deposited lp token
     */
    function _totalDeposit() internal view returns (uint256) {
        ILPStaking.UserInfo memory info = staking.userInfo(pid, address(this));
        return info.amount;
    }

    /**
     * @notice Stake lp token
     */
    function _deposit(uint256 amount) private {
        sourceToken.safeApprove(address(staking), amount);
        staking.deposit(pid, amount);
    }

    /**
     * @notice Transfer all yield tokens to vault
     */
    function _transferYield() internal returns (uint256 amount) {
        amount = yieldToken.balanceOf(address(this));
        yieldToken.safeTransfer(msg.sender, amount);
    }
}
