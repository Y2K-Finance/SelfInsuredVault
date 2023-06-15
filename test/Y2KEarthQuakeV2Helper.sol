// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Helper.sol";

import "y2k-earthquake/src/v2/VaultFactoryV2.sol";
import "y2k-earthquake/src/v2/TimeLock.sol";
import "y2k-earthquake/src/v2/VaultV2.sol";
import "y2k-earthquake/src/v2/Controllers/ControllerPeggedAssetV2.sol";
import "y2k-earthquake/src/v2/interfaces/IWETH.sol";

import {Y2KEarthquakeV2InsuranceProvider} from "../src/providers/Y2KEarthquakeV2InsuranceProvider.sol";

contract Y2KEarthQuakeV2Helper is Helper {
    using FixedPointMathLib for uint256;

    VaultFactoryV2 public factoryV2;
    ControllerPeggedAssetV2 public controllerV2;
    Y2KEarthquakeV2InsuranceProvider public insuranceProviderV2;

    function setUp() public virtual {
        TimeLock timelock = new TimeLock(ADMIN);

        factoryV2 = new VaultFactoryV2(WETH, TREASURY, address(timelock));

        controllerV2 = new ControllerPeggedAssetV2(
            address(factoryV2),
            ARBITRUM_SEQUENCER,
            TREASURY
        );

        insuranceProviderV2 = new Y2KEarthquakeV2InsuranceProvider(
            address(factoryV2)
        );

        factoryV2.whitelistController(address(controllerV2));
    }

    function createEndEpochMarketV2(
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
        address oracle = address(0x3);
        uint256 strike = uint256(0x2);
        string memory name = string("USD Coin");
        string memory symbol = string("USDC");

        (premium, collateral, marketId) = factoryV2.createNewMarket(
            VaultFactoryV2.MarketConfigurationCalldata(
                address(0x11111),
                strike,
                oracle,
                WETH,
                name,
                symbol,
                address(controllerV2)
            )
        );

        (epochId, ) = factoryV2.createEpoch(marketId, begin, end, fee);
    }

    function createDepegMarketV2(
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
        //create depeg market
        string memory name = string("USD Coin");
        string memory symbol = string("USDC");

        uint256 depegStrike = uint256(2 ether);
        (premium, collateral, marketId) = factoryV2.createNewMarket(
            VaultFactoryV2.MarketConfigurationCalldata(
                USDC_TOKEN,
                depegStrike,
                USDC_CHAINLINK,
                WETH,
                name,
                symbol,
                address(controllerV2)
            )
        );

        //create epoch for depeg
        (epochId, ) = factoryV2.createEpoch(marketId, begin, end, fee);
    }

    function helperCalculateFeeAdjustedValueV2(
        uint256 amount
    ) internal view returns (uint256) {
        return amount - amount.mulDivUp(fee, 10000);
    }
}
