// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {IERC1155} from "openzeppelin/token/ERC1155/IERC1155.sol";
import {ERC1155Holder} from "openzeppelin/token/ERC1155/utils/ERC1155Holder.sol";
import {ReentrancyGuard} from "openzeppelin/security/ReentrancyGuard.sol";

import {IYieldSource} from "../interfaces/IYieldSource.sol";
import {IInsuranceProvider} from "../interfaces/IInsuranceProvider.sol";

// TODO Shortfalls
// - other emissions
// - accurate share calculation(shares deposited during epoch is not eligible for that epoch)
// - calc payout based on deposited rewards

// we assume all markets accept the same token

/// @title Self Insured Vault(SIV) contract
/// @author Y2K Finance
/// @dev All function calls are currently implemented without side effects
contract SelfInsuredVault is Ownable, ERC1155Holder, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeCast for int256;

    struct UserInfo {
        uint256 share;
        int256 payoutDebt;
        int256 emissionsDebt;
    }

    struct MarketInfo {
        address provider;
        uint256 marketId;
        uint256 premiumWeight;
        uint256 collateralWeight;
    }

    uint256 public constant PRECISION_FACTOR = 10 ** 18;
    uint256 public constant MAX_MARKETS = 10;

    // -- Global State -- //

    /// @notice Token for yield
    IERC20 public immutable depositToken;

    /// @notice Token to be paid in for insurance
    IERC20 public immutable paymentToken;

    /// @notice Token to be paid in for insurance
    IERC20 public immutable emissionsToken;

    /// @notice Yield source contract
    IYieldSource public immutable yieldSource;

    /// @notice Array of Market Ids for investment
    MarketInfo[] public markets;

    /// @notice Total weight
    uint256 public totalWeight;

    // -- Share and Payout Info -- //

    /// @notice Global payout per share
    uint256 public accPayoutPerShare;

    /// @notice Global emissions per share
    uint256 public accEmissionsPerShare;

    /// @notice User Share info
    mapping(address => UserInfo) public userInfos;

    // -- Events -- //

    /// @notice Emitted when `user` claimed payout
    event ClaimPayouts(address indexed user, uint256 payout);

    /// @notice Emitted when `user` claimed emissions
    event ClaimEmissions(address indexed user, uint256 emissions);

    // -- Errors -- //
    error AddressZero();
    error MaximumMarkets();
    error MarketNotExists();
    error InvalidMarketIndex();
    error InvalidEmissionsToken();
    error InvalidPaymentToken();
    error NextEpochNotPurchasable();
    error AmountZero();

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Contract constructor
     * @param _paymentToken Token used for premium
     * @param _yieldSource Yield source contract address
     * @param _emissionsToken Carousel Emissions token
     */
    constructor(
        address _paymentToken,
        address _yieldSource,
        address _emissionsToken
    ) {
        if (_yieldSource == address(0)) revert AddressZero();
        if (_paymentToken == address(0)) revert AddressZero();

        depositToken = IYieldSource(_yieldSource).sourceToken();
        paymentToken = IERC20(_paymentToken);
        yieldSource = IYieldSource(_yieldSource);
        emissionsToken = IERC20(_emissionsToken);
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Add a new insurance provider
     * @param _provider Insurance provider being used as router
     * @param _marketId Market id
     * @param _premiumWeight Weight of premium vault inside market
     * @param _collateralWeight Weight of collateral vault inside market
     */
    function addMarket(
        address _provider, // v1, v2
        uint256 _marketId,
        uint256 _premiumWeight,
        uint256 _collateralWeight
    ) external onlyOwner {
        if (markets.length >= MAX_MARKETS) revert MaximumMarkets();

        // verify emissionsToken if it's carousel
        address emisToken = IInsuranceProvider(_provider).emissionsToken();
        if (emisToken != address(0) && IERC20(emisToken) != emissionsToken) {
            revert InvalidEmissionsToken();
        }

        // verify payment token of the market
        address payToken = IInsuranceProvider(_provider).paymentToken(_marketId);
        if (payToken != address(paymentToken)) revert InvalidPaymentToken();

        address[2] memory vaults = IInsuranceProvider(_provider).getVaults(
            _marketId
        );
        if (vaults[0] == address(0) || vaults[1] == address(0)) {
            revert MarketNotExists();
        }

        IERC1155(vaults[0]).setApprovalForAll(_provider, true);
        IERC1155(vaults[1]).setApprovalForAll(_provider, true);

        totalWeight += _premiumWeight + _collateralWeight;
        markets.push(
            MarketInfo(_provider, _marketId, _premiumWeight, _collateralWeight)
        );
    }

    /**
     * @notice Set weight of market
     * @param index of market
     * @param _premiumWeight new weight of premium vault
     * @param _collateralWeight new weight of collateral vault
     */
    function setWeight(
        uint256 index,
        uint256 _premiumWeight,
        uint256 _collateralWeight
    ) external onlyOwner {
        if (index >= markets.length) revert InvalidMarketIndex();
        totalWeight =
            totalWeight +
            _premiumWeight +
            _collateralWeight -
            markets[index].premiumWeight -
            markets[index].collateralWeight;
        markets[index].premiumWeight = _premiumWeight;
        markets[index].collateralWeight = _collateralWeight;
    }

    /**
     * @notice Purchase Insurance
     */
    function purchaseInsuranceForNextEpoch() external onlyOwner {
        if (totalWeight == 0) return;

        uint256 totalYield = yieldSource.pendingYield();
        (, uint256 actualOut) = yieldSource.claimAndConvert(
            address(paymentToken),
            totalYield
        );

        // Purchase insurance via Y2K
        for (uint256 i = 0; i < markets.length; i++) {
            MarketInfo memory market = markets[i];
            IInsuranceProvider provider = IInsuranceProvider(market.provider);
            if (!provider.isNextEpochPurchasable(market.marketId)) {
                revert NextEpochNotPurchasable();
            }

            uint256 premiumAmount = (actualOut * market.premiumWeight) /
                totalWeight;
            uint256 collateralAmount = (actualOut * market.collateralWeight) /
                totalWeight;
            uint256 totalAmount = premiumAmount + collateralAmount;
            paymentToken.safeApprove(address(provider), totalAmount);
            provider.purchaseForNextEpoch(
                market.marketId,
                premiumAmount,
                collateralAmount
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                                VIEWERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns count of markets
     */
    function marketsLength() public view returns (uint256) {
        return markets.length;
    }

    /**
     * @notice Returns if emission is set for this Vault
     */
    function isEmissionsEnabled() public view returns (bool) {
        return address(emissionsToken) != address(0);
    }

    /**
     * @notice Returns pending payouts of an insurance
     */
    function pendingInsurancePayouts() public view returns (uint256 pending) {
        for (uint256 i = 0; i < markets.length; i++) {
            IInsuranceProvider provider = IInsuranceProvider(
                markets[i].provider
            );
            pending += provider.pendingPayouts(markets[i].marketId);
        }
    }

    /**
     * @notice Returns pending emissions of an insurance
     */
    function pendingInsuranceEmissions() public view returns (uint256 pending) {
        for (uint256 i = 0; i < markets.length; i++) {
            IInsuranceProvider provider = IInsuranceProvider(
                markets[i].provider
            );
            pending += provider.pendingEmissions(markets[i].marketId);
        }
    }

    /**
     * @notice Returns claimable payouts of `user`
     * @param user address for payout
     */
    function pendingPayouts(
        address user
    ) public view returns (uint256 pending) {
        UserInfo storage info = userInfos[user];
        uint256 newAccPayoutPerShare = accPayoutPerShare;
        uint256 totalShares = yieldSource.totalDeposit();
        if (totalShares != 0) {
            uint256 newPayout = pendingInsurancePayouts();
            newAccPayoutPerShare =
                newAccPayoutPerShare +
                (newPayout * PRECISION_FACTOR) /
                totalShares;
        }
        pending = (int256(
            (info.share * newAccPayoutPerShare) / PRECISION_FACTOR
        ) - info.payoutDebt).toUint256();
    }

    /**
     * @notice Returns claimable emissions of `user`
     * @param user address for receive
     */
    function pendingEmissions(
        address user
    ) public view returns (uint256 pending) {
        UserInfo storage info = userInfos[user];
        uint256 newAccEmitPerShare = accEmissionsPerShare;
        uint256 totalShares = yieldSource.totalDeposit();
        if (totalShares != 0) {
            uint256 newEmissions = pendingInsuranceEmissions();
            newAccEmitPerShare +=
                (newEmissions * PRECISION_FACTOR) /
                totalShares;
        }
        pending = (int256(
            (info.share * newAccEmitPerShare) / PRECISION_FACTOR
        ) - info.emissionsDebt).toUint256();
    }

    /*//////////////////////////////////////////////////////////////
                                USER OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposit to SIV
     * @param amount of `paymentToken`
     * @param receiver for share
     */
    function deposit(uint256 amount, address receiver) public nonReentrant {
        if (amount == 0) revert AmountZero();
        if (receiver == address(0)) revert AddressZero();

        claimVaults();

        depositToken.safeTransferFrom(msg.sender, address(this), amount);
        if (depositToken.allowance(address(this), address(yieldSource)) != 0) {
            depositToken.safeApprove(address(yieldSource), 0);
        }
        depositToken.safeApprove(address(yieldSource), amount);
        yieldSource.deposit(amount);

        UserInfo storage user = userInfos[receiver];
        user.share += amount;
        user.payoutDebt += int256(
            (amount * accPayoutPerShare) / PRECISION_FACTOR
        );
        user.emissionsDebt += int256(
            (amount * accEmissionsPerShare) / PRECISION_FACTOR
        );
    }

    /**
     * @notice Withdraw assets
     * @param amount to withdraw
     * @param to receiver address
     */
    function withdraw(uint256 amount, address to) public nonReentrant {
        if (amount == 0) revert AmountZero();
        if (to == address(0)) revert AddressZero();

        claimVaults();

        UserInfo storage user = userInfos[msg.sender];
        user.payoutDebt -= int256(
            (amount * accPayoutPerShare) / PRECISION_FACTOR
        );
        user.emissionsDebt -= int256(
            (amount * accEmissionsPerShare) / PRECISION_FACTOR
        );
        user.share -= amount;

        yieldSource.withdraw(amount, false, to);
    }

    /**
     * @notice Claim payouts
     */
    function claimPayouts() public nonReentrant {
        claimVaults();

        UserInfo storage user = userInfos[msg.sender];
        int256 accPayout = int256(
            (user.share * accPayoutPerShare) / PRECISION_FACTOR
        );
        uint256 pendingPayout = (accPayout - user.payoutDebt).toUint256();
        user.payoutDebt = accPayout;

        if (pendingPayout == 0) return;
        paymentToken.safeTransfer(msg.sender, pendingPayout);

        emit ClaimPayouts(msg.sender, pendingPayout);
    }

    /**
     * @notice Claim emissions
     */
    function claimEmissions() public nonReentrant {
        if (!isEmissionsEnabled()) return;

        claimVaults();

        UserInfo storage user = userInfos[msg.sender];
        int256 accEmissions = int256(
            (user.share * accEmissionsPerShare) / PRECISION_FACTOR
        );
        uint256 pendingEmits = (accEmissions - user.emissionsDebt).toUint256();
        user.emissionsDebt = accEmissions;

        if (pendingEmits == 0) return;
        emissionsToken.safeTransfer(msg.sender, pendingEmits);

        emit ClaimEmissions(msg.sender, pendingEmits);
    }

    /**
     * @notice Claim payout of a vault
     */
    function claimVaults() public {
        uint256 totalShares = yieldSource.totalDeposit();
        uint256 newPayout;
        uint256 currentEmissionBalance;
        if (isEmissionsEnabled()) {
            currentEmissionBalance = emissionsToken.balanceOf(address(this));
        }
        for (uint256 i = 0; i < markets.length; i++) {
            IInsuranceProvider provider = IInsuranceProvider(
                markets[i].provider
            );
            newPayout += provider.claimPayouts(markets[i].marketId);
        }
        if (totalShares != 0) {
            accPayoutPerShare += (newPayout * PRECISION_FACTOR) / totalShares;

            if (isEmissionsEnabled()) {
                uint256 newEmissions = emissionsToken.balanceOf(address(this)) -
                    currentEmissionBalance;
                accEmissionsPerShare +=
                    (newEmissions * PRECISION_FACTOR) /
                    totalShares;
            }
        }
    }
}
