// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Helper.sol";

import {IWETH} from "y2k-earthquake/src/legacy_v1/interfaces/IWETH.sol";
import {MintableToken} from "y2k-earthquake/test/v2/MintableToken.sol";

import {TimeLock} from "y2k-earthquake/src/v2/TimeLock.sol";

import {Controller} from "y2k-earthquake/src/legacy_v1/Controller.sol";
import {ControllerPeggedAssetV2} from "y2k-earthquake/src/v2/Controllers/ControllerPeggedAssetV2.sol";

import "y2k-earthquake/src/legacy_v1/Vault.sol";
import {VaultV2} from "y2k-earthquake/src/v2/VaultV2.sol";
import {Carousel} from "y2k-earthquake/src/v2/Carousel/Carousel.sol";

import {VaultFactoryV2} from "y2k-earthquake/src/v2/VaultFactoryV2.sol";
import {VaultFactory} from "y2k-earthquake/src/legacy_v1/VaultFactory.sol";
import {CarouselFactory} from "y2k-earthquake/src/v2/Carousel/CarouselFactory.sol";

import {Y2KEarthquakeV1InsuranceProvider} from "../src/providers/Y2KEarthquakeV1InsuranceProvider.sol";
import {Y2KEarthquakeV2InsuranceProvider} from "../src/providers/Y2KEarthquakeV2InsuranceProvider.sol";
import {Y2KEarthquakeCarouselInsuranceProvider} from "../src/providers/Y2KEarthquakeCarouselInsuranceProvider.sol";

contract Y2KEarthQuakeHelper is Helper {
    using FixedPointMathLib for uint256;

    Controller public controllerV1;
    ControllerPeggedAssetV2 public controllerV2;
    ControllerPeggedAssetV2 public carouselController;

    VaultFactory public factoryV1;
    VaultFactoryV2 public factoryV2;
    CarouselFactory public carouselFactory;

    Y2KEarthquakeV1InsuranceProvider public insuranceProviderV1;
    Y2KEarthquakeV2InsuranceProvider public insuranceProviderV2;
    Y2KEarthquakeCarouselInsuranceProvider public carouselInsuranceProvider;

    // carousel data
    address emissionsToken = address(new MintableToken("Emissions Token", "EMT"));
    uint256 relayerFee = 2 gwei;
    uint256 depositFee = 50;

    uint256 premiumEmissions = 1000 ether;
    uint256 collatEmissions = 100 ether;

    string name = string("USD Coin");
    string symbol = string("USDC");

    function setUp() public virtual {
        TimeLock timelock = new TimeLock(ADMIN);

        factoryV1 = new VaultFactory(TREASURY, WETH, address(timelock));
        factoryV2 = new VaultFactoryV2(WETH, TREASURY, address(timelock));
        carouselFactory = new CarouselFactory(
            WETH,
            TREASURY,
            address(timelock),
            emissionsToken
        );

        controllerV1 = new Controller(address(factoryV1), ARBITRUM_SEQUENCER);
        controllerV2 = new ControllerPeggedAssetV2(
            address(factoryV2),
            ARBITRUM_SEQUENCER,
            TREASURY
        );
        carouselController = new ControllerPeggedAssetV2(
            address(carouselFactory),
            ARBITRUM_SEQUENCER,
            TREASURY
        );

        insuranceProviderV1 = new Y2KEarthquakeV1InsuranceProvider(
            address(factoryV1)
        );
        insuranceProviderV2 = new Y2KEarthquakeV2InsuranceProvider(
            address(factoryV2)
        );
        carouselInsuranceProvider = new Y2KEarthquakeCarouselInsuranceProvider(
            address(carouselFactory)
        );

        factoryV1.setController(address(controllerV1));
        factoryV2.whitelistController(address(controllerV2));
        carouselFactory.whitelistController(address(carouselController));
    }

    /************************ V1 ************************/

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
        int256 strike = int256(0x2);
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

    /*********************** V2 ************************/

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

    /*********************** Carousel ************************/

    function createEndEpochMarketCarousel(
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

        (premium, collateral, marketId) = carouselFactory
            .createNewCarouselMarket(
                CarouselFactory.CarouselMarketConfigurationCalldata(
                    address(0x11111),
                    strike,
                    oracle,
                    WETH,
                    name,
                    symbol,
                    address(carouselController),
                    relayerFee,
                    depositFee,
                    1 ether
                )
            );

        // fund treasury
        deal(emissionsToken, TREASURY, 5000 ether, true);
        // approve emissions token to factoryV2
        vm.startPrank(TREASURY);
        MintableToken(emissionsToken).approve(
            address(carouselFactory),
            5000 ether
        );
        vm.stopPrank();

        (epochId, ) = carouselFactory.createEpochWithEmissions(
            marketId,
            begin,
            end,
            fee,
            premiumEmissions,
            collatEmissions
        );
    }
}
