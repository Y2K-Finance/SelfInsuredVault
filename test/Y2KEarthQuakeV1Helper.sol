// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Helper.sol";

import "y2k-earthquake/src/legacy_v1/VaultFactory.sol";
import "y2k-earthquake/src/legacy_v1/Vault.sol";
import "y2k-earthquake/src/legacy_v1/Controller.sol";
import "y2k-earthquake/src/legacy_v1/interfaces/IWETH.sol";

import {Y2KEarthquakeV1InsuranceProvider} from "../src/providers/Y2KEarthquakeV1InsuranceProvider.sol";

contract Y2KEarthQuakeV1Helper is Helper {
    using FixedPointMathLib for uint256;

    VaultFactory public factoryV1;
    Controller public controllerV1;
    Y2KEarthquakeV1InsuranceProvider public insuranceProviderV1;

    function setUp() public virtual {
        TimeLock timelock = new TimeLock(ADMIN);

        factoryV1 = new VaultFactory(TREASURY, WETH, address(timelock));

        controllerV1 = new Controller(address(factoryV1), ARBITRUM_SEQUENCER);

        insuranceProviderV1 = new Y2KEarthquakeV1InsuranceProvider(
            address(factoryV1)
        );

        factoryV1.setController(address(controllerV1));
    }

    function createEndEpochMarketV1(
        uint40 begin,
        uint40 end
    )
        public
        returns (
            address premium,
            address collateral,
            uint256 marketId,
            uint256 epochId
        )
    {
        //create end epoch market
        int256 strike = int256(0x2);
        string memory name = string("USD Coin");

        (premium, collateral) = factoryV1.createNewMarket(
            fee,
            WETH,
            strike,
            begin,
            end,
            USDC_CHAINLINK,
            name
        );
        marketId = factoryV1.marketIndex();
        epochId = end;
    }

    function createEpochV1(
        uint256 marketId,
        uint40 begin,
        uint40 end
    ) public returns (uint256 epochId) {
        factoryV1.deployMoreAssets(marketId, begin, end, fee);
        epochId = end;
    }

    function helperCalculateFeeAdjustedValueV1(
        uint256 amount
    ) internal view returns (uint256) {
        return amount - amount.mulDivUp(fee, 1000);
    }
}
