// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IEarthquake} from "../interfaces/earthquake/IEarthquake.sol";
import {IEarthquakeFactory} from "../interfaces/earthquake/IEarthquakeFactory.sol";

library EarthquakGetter {
    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Returns emissions token address.
     */
    function emissionsToken(IEarthquake vault) external view returns (address) {
        try vault.emissionsToken() returns (address token) {
            return token;
        } catch {
            return address(0);
        }
    }

    /**
     * @notice Returns vault addresses.
     * @param marketId Market Id
     */
    function paymentToken(
        uint256 marketId,
        IEarthquakeFactory factory
    ) external view returns (address) {
        address[2] memory vaults = getVaults(marketId, factory);
        return IEarthquake(vaults[0]).asset();
    }

    /**
     * @notice Returns vault addresses.
     * @param marketId Market Id
     */
    function getVaults(
        uint256 marketId,
        IEarthquakeFactory factory
    ) public view returns (address[2] memory) {
        return factory.getVaults(marketId);
    }

    /**
     * @notice Returns the current epoch.
     * @dev If epoch iteration takes long, then we can think of binary search
     * @param vault Earthquake vault
     */
    function currentEpoch(IEarthquake vault) public view returns (uint256) {
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
    function nextEpoch(IEarthquake vault) public view returns (uint256) {
        uint256 len = vault.getEpochsLength();
        if (len == 0) return 0;
        uint256 epochId = vault.epochs(len - 1);
        (uint40 epochBegin, ) = vault.getEpochConfig(epochId);
        if (block.timestamp > epochBegin) return 0;
        return epochId;
    }

    /**
     * @notice Is next epoch purchasable.
     * @param marketId Market Id
     */
    function isNextEpochPurchasable(
        uint256 marketId,
        IEarthquakeFactory factory
    ) external view returns (bool) {
        // TODO: This isn't implemented in Carousel
        address[2] memory vaults = getVaults(marketId, factory);
        IEarthquake vault = IEarthquake(vaults[0]);
        uint256 id = nextEpoch(vault);
        return id > 0 && block.timestamp <= vault.idEpochBegin(id);
    }

    /**
     * @notice Pending payouts.
     * @param marketId Market Id
     */
    function pendingPayouts(
        uint256 marketId,
        uint256 nextEpochIndexToClaim,
        IEarthquakeFactory factory
    ) external view returns (uint256 pending) {
        address[2] memory vaults = factory.getVaults(marketId);
        uint256[] memory epochs = factory.getEpochsByMarketId(marketId);

        IEarthquake premium = IEarthquake(vaults[0]);
        IEarthquake collateral = IEarthquake(vaults[1]);

        for (uint256 i = nextEpochIndexToClaim; i < epochs.length; i++) {
            // TODO: This logic differs on V1 and Carousel
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
        uint256 marketId,
        uint256 nextEpochIndexToClaim,
        IEarthquakeFactory factory
    ) external view returns (uint256 pending) {
        // TODO: Returns 0 if it's V1 and V2

        address[2] memory vaults = factory.getVaults(marketId);
        uint256[] memory epochs = factory.getEpochsByMarketId(marketId);

        IEarthquake premium = IEarthquake(vaults[0]);
        IEarthquake collateral = IEarthquake(vaults[1]);

        for (uint256 i = nextEpochIndexToClaim; i < epochs.length; i++) {
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

    function purchaseForNextEpoch() external pure returns (uint256) {
        return 0;
    }

    function claimPayouts() external pure returns (uint256) {
        return 0;
    }
}
