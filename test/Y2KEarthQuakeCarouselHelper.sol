// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./Helper.sol";

import "y2k-earthquake/src/v2/TimeLock.sol";
import "y2k-earthquake/src/v2/Carousel/Carousel.sol";
import "y2k-earthquake/src/v2/Carousel/CarouselFactory.sol";
import "y2k-earthquake/src/v2/Controllers/ControllerPeggedAssetV2.sol";
import "y2k-earthquake/test/v2/MintableToken.sol";
import "y2k-earthquake/src/v2/interfaces/IWETH.sol";

import {Y2KEarthquakeCarouselInsuranceProvider} from "../src/providers/Y2KEarthquakeCarouselInsuranceProvider.sol";

contract Y2KEarthQuakeCarouselHelper is Helper {
    using FixedPointMathLib for uint256;

    CarouselFactory public carouselFactory;
    ControllerPeggedAssetV2 public carouselController;
    Y2KEarthquakeCarouselInsuranceProvider public carouselInsuranceProvider;
    address emissionsToken;
    uint256 relayerFee;
    uint256 depositFee;

    uint256 premiumEmissions = 1000 ether;
    uint256 collatEmissions = 100 ether;

    function setUp() public virtual {
        TimeLock timelock = new TimeLock(ADMIN);

        emissionsToken = address(new MintableToken("Emissions Token", "EMT"));

        carouselFactory = new CarouselFactory(
            WETH,
            TREASURY,
            address(timelock),
            emissionsToken
        );

        carouselController = new ControllerPeggedAssetV2(
            address(carouselFactory),
            ARBITRUM_SEQUENCER,
            TREASURY
        );

        carouselInsuranceProvider = new Y2KEarthquakeCarouselInsuranceProvider(
            address(carouselFactory)
        );

        carouselFactory.whitelistController(address(carouselController));

        relayerFee = 2 gwei;
        depositFee = 50; // 1%
    }

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
        string memory name = string("USD Coin");
        string memory symbol = string("USDC");

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

    function carouselHelperCalculateFeeAdjustedValue(
        uint256 amount
    ) internal view returns (uint256) {
        return amount - amount.mulDivUp(fee, 10000);
    }
}
