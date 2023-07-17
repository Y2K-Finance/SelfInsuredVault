// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Math} from "openzeppelin/utils/math/Math.sol";

import {ISemiFungibleVault} from "y2k-earthquake/src/v2/interfaces/ISemiFungibleVault.sol";

import {IInsuranceProvider} from "../interfaces/IInsuranceProvider.sol";
import {ICarouselFactoryExtended} from "../interfaces/earthquake/ICarouselFactoryExtended.sol";
import {ICarouselExtended} from "../interfaces/earthquake/ICarouselExtended.sol";

/// @title Insurance Provider for Y2k Earthquake v2
/// @author Y2K Finance
/// @dev All function calls are currently implemented without side effects
contract Y2KEarthquakeCarouselInsuranceProvider is IInsuranceProvider {
    using SafeERC20 for IERC20;

    /// @notice Earthquake vault factory
    ICarouselFactoryExtended public immutable carouselFactory;

    /// @notice Last claimed epoch index; Market Id => Epoch Index
    mapping(address => mapping(uint256 => uint256))
        public nextEpochIndexToClaim;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Constructor
     * @param _carouselFactory Address of Earthquake v2 vault factory.
     */
    constructor(address _carouselFactory) {
        if (_carouselFactory == address(0)) revert AddressZero();
        carouselFactory = ICarouselFactoryExtended(_carouselFactory);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns emissions token address.
     */
    function emissionsToken() external view returns (address) {
        return carouselFactory.emissionsToken();
    }

    /**
     * @notice Returns vault addresses.
     * @param marketId Market Id
     */
    function paymentToken(uint256 marketId) external view returns (address) {
        address[2] memory vaults = getVaults(marketId);
        return address(ISemiFungibleVault(vaults[0]).asset());
    }

    /**
     * @notice Returns vault addresses.
     * @param marketId Market Id
     */
    function getVaults(
        uint256 marketId
    ) public view returns (address[2] memory) {
        return carouselFactory.getVaults(marketId);
    }

    /**
     * @notice Returns the current epoch.
     * @dev If epoch iteration takes long, then we can think of binary search
     * @param vault Earthquake vault
     */
    function currentEpoch(
        ICarouselExtended vault
    ) public view returns (uint256) {
        uint256 len = vault.getEpochsLength();
        if (len > 0) {
            for (uint256 i = len - 1; i >= 0; i--) {
                uint256 epochId = vault.epochs(i);
                (uint40 epochBegin, uint40 epochEnd) = vault.getEpochConfig(
                    epochId
                );
                if (block.timestamp > epochEnd) {
                    break;
                }

                if (
                    block.timestamp > epochBegin &&
                    block.timestamp <= epochEnd &&
                    !vault.epochResolved(epochId)
                ) {
                    return epochId;
                }
            }
        }
        return 0;
    }

    /**
     * @notice Returns the next epoch.
     * @param vault Earthquake vault
     */
    function nextEpoch(ICarouselExtended vault) public view returns (uint256) {
        uint256 len = vault.getEpochsLength();
        if (len == 0) return 0;
        uint256 epochId = vault.epochs(len - 1);
        (uint40 epochBegin, ) = vault.getEpochConfig(epochId);
        if (block.timestamp > epochBegin) return 0;
        return epochId;
    }

    /**
     * @notice Is next epoch purchasable.
     */
    function isNextEpochPurchasable(uint256) external pure returns (bool) {
        return true;
        // address[2] memory vaults = carouselFactory.getVaults(marketId);
        // ICarouselExtended vault = ICarouselExtended(vaults[0]);
        // uint256 id = nextEpoch(vault);
        // (uint40 epochBegin, ) = vault.getEpochConfig(id);
        // return id > 0 && block.timestamp <= epochBegin;
    }

    /**
     * @notice Pending payouts.
     * @param marketId Market Id
     */
    function pendingPayouts(
        uint256 marketId
    ) external view returns (uint256 pending) {
        address[2] memory vaults = carouselFactory.getVaults(marketId);
        uint256[] memory epochs = carouselFactory.getEpochsByMarketId(marketId);

        ICarouselExtended premium = ICarouselExtended(vaults[0]);
        ICarouselExtended collateral = ICarouselExtended(vaults[1]);

        for (
            uint256 i = nextEpochIndexToClaim[msg.sender][marketId];
            i < epochs.length;
            i++
        ) {
            (, uint40 epochEnd) = premium.getEpochConfig(epochs[i]);
            if (
                block.timestamp <= epochEnd ||
                !premium.epochResolved(epochs[i]) ||
                !collateral.epochResolved(epochs[i])
            ) {
                break;
            }

            uint256 premiumShares = premium.balanceOf(msg.sender, epochs[i]);
            uint256 collateralShares = collateral.balanceOf(
                msg.sender,
                epochs[i]
            );
            if (premiumShares > 0)
                pending += premium.previewWithdraw(epochs[i], premiumShares);
            if (collateralShares > 0)
                pending += collateral.previewWithdraw(
                    epochs[i],
                    collateralShares
                );
        }
    }

    /**
     * @notice Pending emissions.
     * @param marketId Market Id
     */
    // NOTE: Returns all emissions
    function pendingEmissions(
        uint256 marketId
    ) external view returns (uint256 pending) {
        address[2] memory vaults = carouselFactory.getVaults(marketId);
        uint256[] memory epochs = carouselFactory.getEpochsByMarketId(marketId);

        ICarouselExtended premium = ICarouselExtended(vaults[0]);
        ICarouselExtended collateral = ICarouselExtended(vaults[1]);

        for (
            uint256 i = nextEpochIndexToClaim[msg.sender][marketId];
            i < epochs.length;
            i++
        ) {
            (, uint40 epochEnd) = premium.getEpochConfig(epochs[i]);
            if (
                block.timestamp <= epochEnd ||
                !premium.epochResolved(epochs[i]) ||
                !collateral.epochResolved(epochs[i])
            ) {
                break;
            }

            uint256 premiumShares = premium.balanceOf(msg.sender, epochs[i]);
            uint256 collateralShares = collateral.balanceOf(
                msg.sender,
                epochs[i]
            );
            pending += premium.previewEmissionsWithdraw(
                epochs[i],
                premiumShares
            );
            pending += collateral.previewEmissionsWithdraw(
                epochs[i],
                collateralShares
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                                OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Purchase next epoch.
     * @param marketId Market Id
     * @param amountPremium Premium amount for insurance
     * @param amountCollateral Collateral amount for insurance
     */
    function purchaseForNextEpoch(
        uint256 marketId,
        uint256 amountPremium,
        uint256 amountCollateral
    ) external {
        (, , address underlyingAsset) = carouselFactory.marketIdInfo(marketId);
        address[2] memory vaults = carouselFactory.getVaults(marketId);
        IERC20(underlyingAsset).safeTransferFrom(
            msg.sender,
            address(this),
            amountPremium + amountCollateral
        );

        uint256 nextEpochId = nextEpoch(ICarouselExtended(vaults[0]));
        if (amountPremium > 0) {
            IERC20(underlyingAsset).safeApprove(vaults[0], amountPremium);
            ICarouselExtended(vaults[0]).deposit(
                nextEpochId,
                amountPremium,
                msg.sender
            );
        }
        if (amountCollateral > 0) {
            IERC20(underlyingAsset).safeApprove(vaults[1], amountCollateral);
            ICarouselExtended(vaults[1]).deposit(
                nextEpochId,
                amountCollateral,
                msg.sender
            );
        }
    }

    /**
     * @notice Claims payout for the resolved epochs.
     * @param marketId Market Id
     */
    // NOTE: The nextEpochIndexToClaim is called by the sender and this changes nextEpochIndexToClaim
    // NOTE: Could this in theory malicious push the epoch index forward?
    function claimPayouts(uint256 marketId) external returns (uint256 amount) {
        uint256[] memory epochs = carouselFactory.getEpochsByMarketId(marketId);
        address[2] memory vaults = carouselFactory.getVaults(marketId);

        ICarouselExtended premium = ICarouselExtended(vaults[0]);
        ICarouselExtended collateral = ICarouselExtended(vaults[1]);

        uint256 i = nextEpochIndexToClaim[msg.sender][marketId];
        for (; i < epochs.length; i++) {
            (, uint40 epochEnd) = premium.getEpochConfig(epochs[i]);
            if (
                block.timestamp <= epochEnd ||
                !premium.epochResolved(epochs[i]) ||
                !collateral.epochResolved(epochs[i])
            ) {
                break;
            }

            uint256 premiumShares = premium.balanceOf(msg.sender, epochs[i]);
            if (premiumShares > 0) {
                amount += premium.withdraw(
                    epochs[i],
                    premiumShares,
                    msg.sender,
                    msg.sender
                );
            }
            uint256 collateralShares = collateral.balanceOf(
                msg.sender,
                epochs[i]
            );
            if (collateralShares > 0) {
                amount += collateral.withdraw(
                    epochs[i],
                    collateralShares,
                    msg.sender,
                    msg.sender
                );
            }
        }
        nextEpochIndexToClaim[msg.sender][marketId] = i;
    }
}
