// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";

import {Y2KEarthQuakeV1Helper, Vault} from "../Y2KEarthQuakeV1Helper.sol";
import {Y2KEarthQuakeV2Helper, IWETH, VaultV2} from "../Y2KEarthQuakeV2Helper.sol";
import {Y2KEarthQuakeCarouselHelper, Carousel} from "../Y2KEarthQuakeCarouselHelper.sol";

import {SelfInsuredVault} from "../../src/vaults/SelfInsuredVault.sol";
import {StargateLPYieldSource} from "../../src/sources/StargateLPYieldSource.sol";

import {IInsuranceProvider} from "../../src/interfaces/IInsuranceProvider.sol";
import {IYieldSource} from "../../src/interfaces/IYieldSource.sol";
import {ILPStaking} from "../../src/interfaces/stargate/ILPStaking.sol";

contract EndToEndSIVTest is Y2KEarthQuakeV2Helper, Y2KEarthQuakeV1Helper, Y2KEarthQuakeCarouselHelper {
    uint256 public constant LP_DEPOSIT_AMOUNT = 1000000000;
    uint256 public constant WETH_DEPOSIT_AMOUNT = 10 ether;

    address public siv;
    address public yieldSource;

    function setUp()
        public
        override(Y2KEarthQuakeV1Helper, Y2KEarthQuakeV2Helper, Y2KEarthQuakeCarouselHelper)
    {
        Y2KEarthQuakeV1Helper.setUp();
        Y2KEarthQuakeV2Helper.setUp();
        Y2KEarthQuakeCarouselHelper.setUp();

        yieldSource = address(
            new StargateLPYieldSource(
                STG_PID,
                STG_LPTOKEN,
                STG_STAKING,
                SUSHISWAP_ROUTER
            )
        );
        siv = address(new SelfInsuredVault(WETH, yieldSource, emissionsToken));

        IYieldSource(yieldSource).transferOwnership(siv);
    }

    // Single v1 epoch with two users
    function testV1EndEpoch() public {
        /******************** Create markets ************************/

        uint40 begin = uint40(block.timestamp - 5 days);
        uint40 end = uint40(block.timestamp - 3 days);
        (
            address premium,
            address collateral,
            uint256 marketId,
            uint256 epochId
        ) = Y2KEarthQuakeV1Helper.createEndEpochMarketV1(begin, end);

        SelfInsuredVault(siv).addMarket(
            address(insuranceProviderV1),
            marketId,
            0, // premium deposit is just done by user
            100 // siv deposits into collateral
        );

        /******************** USER deposit ************************/

        vm.warp(begin - 1 days);

        vm.startPrank(USER);

        // get weth
        vm.deal(USER, WETH_DEPOSIT_AMOUNT);
        IWETH(WETH).deposit{value: WETH_DEPOSIT_AMOUNT}();

        // deposit into premium
        IERC20(WETH).approve(premium, WETH_DEPOSIT_AMOUNT);
        Vault(premium).deposit(epochId, WETH_DEPOSIT_AMOUNT, USER);

        // deposit into SIV, both for USER and USER2
        IERC20(STG_LPTOKEN).approve(siv, LP_DEPOSIT_AMOUNT * 2);
        SelfInsuredVault(siv).deposit(LP_DEPOSIT_AMOUNT, USER);
        SelfInsuredVault(siv).deposit(LP_DEPOSIT_AMOUNT, USER2);

        vm.stopPrank();

        /******************** Purchase Insurance ************************/

        // generate yields
        vm.roll(block.number + 100000000);

        // check farming balance
        uint256 SIV_WETH_AMOUNT = IYieldSource(yieldSource).pendingYieldInToken(
            WETH
        );
        SelfInsuredVault(siv).purchaseInsuranceForNextEpoch();

        // none left at siv
        assertEq(IERC20(WETH).balanceOf(siv), 0);

        // check deposit balances
        assertEq(Vault(premium).balanceOf(USER, epochId), WETH_DEPOSIT_AMOUNT);
        assertEq(Vault(collateral).balanceOf(siv, epochId), SIV_WETH_AMOUNT);

        /******************** End Epoch ************************/

        // warp to epoch end
        vm.warp(end + 1 days);

        // trigger end of epoch
        controllerV1.triggerEndEpoch(marketId, epochId);

        uint256 amountWithoutFee = SIV_WETH_AMOUNT + WETH_DEPOSIT_AMOUNT;

        // check vault balances on withdraw
        assertEq(
            Vault(premium).previewWithdraw(epochId, WETH_DEPOSIT_AMOUNT),
            0
        );
        assertEq(
            Vault(collateral).previewWithdraw(epochId, SIV_WETH_AMOUNT),
            amountWithoutFee
        );

        /******************** Claim Payout ************************/

        // check user balance
        assertEq(
            SelfInsuredVault(siv).pendingPayouts(USER),
            amountWithoutFee / 2
        );
        assertEq(
            SelfInsuredVault(siv).pendingPayouts(USER2),
            amountWithoutFee / 2
        );

        SelfInsuredVault(siv).claimVaults();

        uint256 amountAfterFee = SIV_WETH_AMOUNT +
            helperCalculateFeeAdjustedValueV1(WETH_DEPOSIT_AMOUNT);

        // check user balance
        assertEq(
            SelfInsuredVault(siv).pendingPayouts(USER),
            amountAfterFee / 2
        );
        assertEq(
            SelfInsuredVault(siv).pendingPayouts(USER2),
            amountAfterFee / 2
        );

        // withdraw from vaults
        vm.prank(USER);
        SelfInsuredVault(siv).claimPayouts();
        vm.prank(USER2);
        SelfInsuredVault(siv).claimPayouts();

        // check remaining balance
        assertEq(Vault(collateral).balanceOf(siv, epochId), 0);
        assertEq(SelfInsuredVault(siv).pendingPayouts(USER), 0);
        assertEq(SelfInsuredVault(siv).pendingPayouts(USER2), 0);

        // check user balance
        assertEq(IERC20(WETH).balanceOf(USER), amountAfterFee / 2);
        assertEq(IERC20(WETH).balanceOf(USER2), amountAfterFee / 2);
    }

    // Single v2 epoch with two users
    function testV2EndEpoch() public {
        /******************** Create markets ************************/

        uint40 begin = uint40(block.timestamp - 5 days);
        uint40 end = uint40(block.timestamp - 3 days);
        (
            address premium,
            address collateral,
            uint256 marketId,
            uint256 epochId
        ) = Y2KEarthQuakeV2Helper.createEndEpochMarket(begin, end);

        SelfInsuredVault(siv).addMarket(
            address(insuranceProvider),
            marketId,
            0, // premium deposit is just done by user
            100 // siv deposits into collateral
        );

        /******************** USER deposit ************************/

        vm.warp(begin - 1 days);

        vm.startPrank(USER);

        // get weth
        vm.deal(USER, WETH_DEPOSIT_AMOUNT);
        IWETH(WETH).deposit{value: WETH_DEPOSIT_AMOUNT}();

        // deposit into premium
        IERC20(WETH).approve(premium, WETH_DEPOSIT_AMOUNT);
        VaultV2(premium).deposit(epochId, WETH_DEPOSIT_AMOUNT, USER);

        // deposit in SIV
        IERC20(STG_LPTOKEN).approve(siv, LP_DEPOSIT_AMOUNT * 2);
        SelfInsuredVault(siv).deposit(LP_DEPOSIT_AMOUNT, USER);
        SelfInsuredVault(siv).deposit(LP_DEPOSIT_AMOUNT, USER2);

        vm.stopPrank();

        /******************** Purchase Insurance ************************/

        // generate yields
        vm.roll(block.number + 100000000);

        // check farming balance
        uint256 SIV_WETH_AMOUNT = IYieldSource(yieldSource).pendingYieldInToken(
            WETH
        );
        SelfInsuredVault(siv).purchaseInsuranceForNextEpoch();

        // none left at siv
        assertEq(IERC20(WETH).balanceOf(siv), 0);

        // check deposit balances
        assertEq(
            VaultV2(premium).balanceOf(USER, epochId),
            WETH_DEPOSIT_AMOUNT
        );
        assertEq(VaultV2(collateral).balanceOf(siv, epochId), SIV_WETH_AMOUNT);

        /******************** End Epoch ************************/

        // warp to epoch end
        vm.warp(end + 1 days);

        // trigger end of epoch
        controller.triggerEndEpoch(marketId, epochId);

        // check vault balances on withdraw
        uint256 amountAfterFee = SIV_WETH_AMOUNT +
            helperCalculateFeeAdjustedValue(WETH_DEPOSIT_AMOUNT);
        assertEq(
            VaultV2(premium).previewWithdraw(epochId, WETH_DEPOSIT_AMOUNT),
            0
        );
        assertEq(
            VaultV2(collateral).previewWithdraw(epochId, SIV_WETH_AMOUNT),
            amountAfterFee
        );

        /******************** Claim Payout ************************/

        // check user balance
        assertEq(
            SelfInsuredVault(siv).pendingPayouts(USER),
            amountAfterFee / 2
        );
        assertEq(
            SelfInsuredVault(siv).pendingPayouts(USER2),
            amountAfterFee / 2
        );

        // withdraw from vaults
        vm.prank(USER);
        SelfInsuredVault(siv).claimPayouts();
        vm.prank(USER2);
        SelfInsuredVault(siv).claimPayouts();

        // check vaults balance
        assertEq(VaultV2(collateral).balanceOf(siv, epochId), 0);
        assertEq(SelfInsuredVault(siv).pendingPayouts(USER), 0);
        assertEq(SelfInsuredVault(siv).pendingPayouts(USER2), 0);

        // check user balance
        assertEq(IERC20(WETH).balanceOf(USER), amountAfterFee / 2);
        assertEq(IERC20(WETH).balanceOf(USER2), amountAfterFee / 2);
    }

    // Single carousel epoch with two users
    function testCarouselEndEpoch() public {
        /******************** Create markets ************************/

        uint40 begin = uint40(block.timestamp - 5 days);
        uint40 end = uint40(block.timestamp - 3 days);
        (
            address premium,
            address collateral,
            uint256 marketId,
            uint256 epochId
        ) = Y2KEarthQuakeCarouselHelper.createEndEpochMarketCarousel(begin, end);

        SelfInsuredVault(siv).addMarket(
            address(carouselInsuranceProvider),
            marketId,
            0, // premium deposit is just done by user
            100 // siv deposits into collateral
        );

        /******************** USER deposit ************************/

        vm.warp(begin - 1 days);

        vm.startPrank(USER);

        // get weth
        vm.deal(USER, WETH_DEPOSIT_AMOUNT);
        IWETH(WETH).deposit{value: WETH_DEPOSIT_AMOUNT}();

        // deposit into premium
        IERC20(WETH).approve(premium, WETH_DEPOSIT_AMOUNT);
        VaultV2(premium).deposit(epochId, WETH_DEPOSIT_AMOUNT, USER);

        // deposit in SIV
        IERC20(STG_LPTOKEN).approve(siv, LP_DEPOSIT_AMOUNT * 2);
        SelfInsuredVault(siv).deposit(LP_DEPOSIT_AMOUNT, USER);
        SelfInsuredVault(siv).deposit(LP_DEPOSIT_AMOUNT, USER2);

        vm.stopPrank();

        /******************** Purchase Insurance ************************/

        // generate yields
        vm.roll(block.number + 100000000);

        // check farming balance
        uint256 SIV_WETH_AMOUNT = IYieldSource(yieldSource).pendingYieldInToken(
            WETH
        );
        SelfInsuredVault(siv).purchaseInsuranceForNextEpoch();

        // none left at siv
        assertEq(IERC20(WETH).balanceOf(siv), 0);

        // check deposit balances
        uint256 premiumShares =  Carousel(premium).balanceOf(USER, epochId);
        uint256 collateralShares = Carousel(collateral).balanceOf(siv, epochId);

        /******************** End Epoch ************************/

        // warp to epoch end
        vm.warp(end + 1 days);

        // trigger end of epoch
        carouselController.triggerEndEpoch(marketId, epochId);

        // check vault balances on withdraw
        uint256 amountAfterFee = Carousel(collateral).previewWithdraw(epochId, collateralShares);

        /******************** Claim Payout ************************/

        // check user balance
        assertEq(
            SelfInsuredVault(siv).pendingPayouts(USER),
            amountAfterFee / 2
        );
        assertEq(
            SelfInsuredVault(siv).pendingPayouts(USER2),
            amountAfterFee / 2
        );
        assertEq(
            SelfInsuredVault(siv).pendingEmissions(USER),
            collatEmissions / 2
        );
        assertEq(
            SelfInsuredVault(siv).pendingEmissions(USER2),
            collatEmissions / 2
        );

        // withdraw from vaults
        vm.prank(USER);
        SelfInsuredVault(siv).claimPayouts();
        vm.prank(USER);
        SelfInsuredVault(siv).claimEmissions();
        vm.prank(USER2);
        SelfInsuredVault(siv).claimPayouts();
        vm.prank(USER2);
        SelfInsuredVault(siv).claimEmissions();

        // check vaults balance
        assertEq(Carousel(collateral).balanceOf(siv, epochId), 0);
        assertEq(SelfInsuredVault(siv).pendingPayouts(USER), 0);
        assertEq(SelfInsuredVault(siv).pendingPayouts(USER2), 0);
        assertEq(SelfInsuredVault(siv).pendingEmissions(USER), 0);
        assertEq(SelfInsuredVault(siv).pendingEmissions(USER2), 0);

        // check user balance
        assertEq(IERC20(WETH).balanceOf(USER), amountAfterFee / 2);
        assertEq(IERC20(WETH).balanceOf(USER2), amountAfterFee / 2);
        assertEq(IERC20(emissionsToken).balanceOf(USER), collatEmissions / 2);
        assertEq(IERC20(emissionsToken).balanceOf(USER2), collatEmissions / 2);
    }

    /**
     * Multiple epochs with several user
     *   v1:    |------ epoch 1 ------|------ epoch 2 ------|
     *   v2:                          |------ epoch 2 ------|
     *   users: |------  USER  -------|---- USER, USER2 ----|
     * 
     * Test flow
     *   1. Create v1 market with epoch 1
     *   2. `USER` deposits
     *   3. Trigger end epoch
     *   4. Create market v2 and add epoch 2 for both markets
     *   5. `USER2` deposits the same amount `USER` did
     *   6. Trigger depeg and end epoch
     *   7. Claim payouts, check the payout amount
     */
    function testCombinedEndToEndEndEpoch() public {
        /******************** Create markets ************************/

        uint40 begin1 = uint40(block.timestamp - 9 days);
        uint40 end1 = uint40(block.timestamp - 7 days);
        uint40 begin2 = uint40(block.timestamp - 5 days);
        uint40 end2 = uint40(block.timestamp - 3 days);
        (
            address premiumV1,
            address collateralV1,
            uint256 marketIdV1,
            uint256 epochId1V1
        ) = Y2KEarthQuakeV1Helper.createEndEpochMarketV1(begin1, end1);
        SelfInsuredVault(siv).addMarket(
            address(insuranceProviderV1),
            marketIdV1,
            100,
            100
        );

        /******************** USER deposit to v1 epoch 1 ************************/

        vm.warp(begin1 - 1 days);
        vm.startPrank(USER);

        // deposit into SIV, only USER
        IERC20(STG_LPTOKEN).approve(siv, LP_DEPOSIT_AMOUNT);
        SelfInsuredVault(siv).deposit(LP_DEPOSIT_AMOUNT, USER);

        vm.stopPrank();

        /******************** Purchase Insurance for epoch 1 ************************/

        // generate yields
        vm.roll(block.number + 100000000);

        // check farming balance
        uint256 SIV_WETH_AMOUNT1 = IYieldSource(yieldSource)
            .pendingYieldInToken(WETH);
        SelfInsuredVault(siv).purchaseInsuranceForNextEpoch();

        // some left due to rounding
        assertEq(IERC20(WETH).balanceOf(siv) < 2, true);

        // check deposit balances
        assertEq(
            Vault(premiumV1).balanceOf(siv, epochId1V1),
            SIV_WETH_AMOUNT1 / 2
        );
        assertEq(
            Vault(collateralV1).balanceOf(siv, epochId1V1),
            SIV_WETH_AMOUNT1 / 2
        );

        /******************** End Epoch ************************/

        // trigger end of epoch
        vm.warp(end1 + 1 days);
        controllerV1.triggerEndEpoch(marketIdV1, epochId1V1);

        // check vault balances on withdraw
        assertEq(
            Vault(premiumV1).previewWithdraw(epochId1V1, SIV_WETH_AMOUNT1 / 2),
            0
        );
        // some left due to rounding
        assertApproxEqAbs(
            Vault(collateralV1).previewWithdraw(epochId1V1, SIV_WETH_AMOUNT1 / 2),
            SIV_WETH_AMOUNT1,
            2
        );

        /******************** Check Payout ************************/

        // check user balance
        assertApproxEqAbs(
            SelfInsuredVault(siv).pendingPayouts(USER),
            SIV_WETH_AMOUNT1,
            2
        );
        assertEq(SelfInsuredVault(siv).pendingPayouts(USER2), 0);

        /******************** Add new markets ************************/

        uint256 epochId2V1 = Y2KEarthQuakeV1Helper.createEpoch(
            marketIdV1,
            begin2,
            end2
        );
        (
            address premiumV2,
            address collateralV2,
            uint256 marketIdV2,
            uint256 epochId2V2
        ) = Y2KEarthQuakeV2Helper.createDepegMarket(begin2, end2);
        SelfInsuredVault(siv).addMarket(
            address(insuranceProvider),
            marketIdV2,
            100,
            100
        );

        /******************** USER2 deposit ************************/

        vm.warp(begin2 - 1 days);
        vm.startPrank(USER);

        // deposit into SIV, only USER
        IERC20(STG_LPTOKEN).approve(siv, LP_DEPOSIT_AMOUNT);
        SelfInsuredVault(siv).deposit(LP_DEPOSIT_AMOUNT, USER2);

        vm.stopPrank();

        /******************** Purchase Insurance for epoch 2 ************************/

        // generate yields
        vm.roll(block.number + 100000000);

        // check farming balance
        uint256 SIV_WETH_AMOUNT2 = IYieldSource(yieldSource)
            .pendingYieldInToken(WETH);
        SelfInsuredVault(siv).purchaseInsuranceForNextEpoch();

        // check deposit balances
        assertEq(
            Vault(premiumV1).balanceOf(siv, epochId2V1),
            SIV_WETH_AMOUNT2 / 4
        );
        assertEq(
            Vault(collateralV1).balanceOf(siv, epochId2V1),
            SIV_WETH_AMOUNT2 / 4
        );
        assertEq(
            VaultV2(premiumV2).balanceOf(siv, epochId2V2),
            SIV_WETH_AMOUNT2 / 4
        );
        assertEq(
            VaultV2(collateralV2).balanceOf(siv, epochId2V2),
            SIV_WETH_AMOUNT2 / 4
        );

        /******************** Trigger Depeg, End ************************/

        // trigger depeg
        vm.warp(end2 - 1 hours);
        controller.triggerDepeg(marketIdV2, epochId2V2);

        // trigger end of epoch
        vm.warp(end2 + 1 days);
        controllerV1.triggerEndEpoch(marketIdV1, epochId2V1);

        // check vault balances on withdraw
        uint256 amountAfterFee = Y2KEarthQuakeV2Helper
            .helperCalculateFeeAdjustedValue(SIV_WETH_AMOUNT2 / 4);
        assertApproxEqAbs(
            VaultV2(premiumV2).previewWithdraw(epochId2V2, SIV_WETH_AMOUNT2 / 4),
            amountAfterFee,
            2
        );
        assertApproxEqAbs(
            VaultV2(collateralV2).previewWithdraw(
                epochId2V2,
                SIV_WETH_AMOUNT2 / 4
            ),
            amountAfterFee,
            2
        );

        /******************** Claim Payout ************************/

        // withdraw from vaults
        vm.prank(USER);
        SelfInsuredVault(siv).claimPayouts();
        vm.prank(USER2);
        SelfInsuredVault(siv).claimPayouts();

        // check remaining balance
        assertEq(SelfInsuredVault(siv).pendingPayouts(USER), 0);
        assertEq(SelfInsuredVault(siv).pendingPayouts(USER2), 0);

        // payout for market 1(v1), all for USER
        uint256 payout1 = SIV_WETH_AMOUNT1 / 2 + Y2KEarthQuakeV1Helper.helperCalculateFeeAdjustedValueV1(SIV_WETH_AMOUNT1 / 2);

        // payout for market 2(v1), for both user
        uint256 payout2V1 = SIV_WETH_AMOUNT2 / 4 + Y2KEarthQuakeV1Helper.helperCalculateFeeAdjustedValueV1(SIV_WETH_AMOUNT2 / 4);
        // payout for market 2(v2), for both user
        uint256 payout2V2 = Y2KEarthQuakeV2Helper.helperCalculateFeeAdjustedValue(SIV_WETH_AMOUNT2 / 2);
        // totla payout
        uint256 payout2 = payout2V1 + payout2V2;

        uint256 userAmount = payout1 + payout2 / 2;
        uint256 user2Amount = payout2 / 2;

        // check user balance
        assertApproxEqAbs(IERC20(WETH).balanceOf(USER), userAmount, 2);
        assertApproxEqAbs(IERC20(WETH).balanceOf(USER2), user2Amount, 2);
    }
}
