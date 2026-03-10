//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {HelperConfig} from "../../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.t.sol";

contract DSCEngineTest is Test {
    DecentralizedStableCoin public dsc;
    DSCEngine public engine;
    HelperConfig public helperConfig;

    address public ethUsdPriceFeed;
    address public weth;
    address public btcUsdPriceFeed;
    address public wbtc;
    uint256 public deployerKey;

    uint256 amountCollateral = 10 ether;
    uint256 amountToMint = 100 ether;
    address public user = address(1);

    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    function setUp() public {
        DeployDSC deployer = new DeployDSC();
        (dsc, engine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = helperConfig.activeNetworkConfig();

        if (block.chainid == 31_337) {
            vm.deal(user, STARTING_USER_BALANCE);
        }

        ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);
    }

    address[] public tokenAddresses;
    address[] public feedAddresses;

    function testRevertsIfTokenLenghtDoesntMatchPriceFeed() public {
        tokenAddresses.push(weth);
        feedAddresses.push(ethUsdPriceFeed);
        feedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 expectedWeth = 0.05 ether;
        uint256 amountWeth = engine.getTokenAmountFromUsd(weth, 100 ether);
        assertEq(amountWeth, expectedWeth);
    }

    function testGetUSdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30_000e18;
        uint256 UsdValue = engine.getUsdValue(weth, ethAmount);
        assertEq(UsdValue, expectedUsd);
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randToken = new ERC20Mock("RAN", "RAN", msg.sender, 1000e8);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedToken.selector, address(randToken)));
        engine.depositCollateral(address(randToken), amountCollateral);
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateral(weth, amountCollateral);
        vm.stopPrank();
        _;
    }

    function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(user);
        assertEq(userBalance, 0);
    }

    function testCanDepositCollateralAndGetAcountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(user);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(amountCollateral, expectedDepositAmount);
    }

    function testRevertsIfMintedDscIsZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertIfNotEnoughCollateral() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, uint256(0)));
        engine.mintDsc(amountToMint);
        vm.stopPrank();
    }

    function testMintDsc() public depositedCollateral {
        vm.startPrank(user);
        engine.mintDsc(amountToMint);
        assertEq(dsc.balanceOf(user), amountToMint);
        (uint256 totalDscMinted,) = engine.getAccountInformation(user);
        assertEq(totalDscMinted, amountToMint);
        vm.stopPrank();
    }

    modifier depositedCollateralAndMintedDsc() {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateral(weth, amountCollateral);
        engine.mintDsc(amountToMint);
        vm.stopPrank();
        _;
    }

    function testBurnDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        dsc.approve(address(engine), amountToMint);
        engine.burnDsc(amountToMint);
        assertEq(dsc.balanceOf(user), 0);
        (uint256 totalDscMinted,) = engine.getAccountInformation(user);
        assertEq(totalDscMinted, 0);
        vm.stopPrank();
    }

    function testRevertIfYouTryToBurnMoreThanYouHave() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        dsc.approve(address(engine), amountToMint);
        vm.expectRevert();
        engine.burnDsc(amountToMint + 1);
        vm.stopPrank();
    }

    function testRevertIfHealthFactorIsBroken() public depositedCollateral {
        // 10 ETH x $2000 = $20,000 kolaterala
        // $20,000 x 50% = $10,000 max DSC
        // mintamo 10,101 DSC — iznad limita
        uint256 amountToMintOverLimit = 10_101e18;
        // HF = ($10,000e18 * 1e18) / 10,101e18 = 990000990000990000
        uint256 expectedHealthFactor = 990000990000990000;

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
        engine.mintDsc(amountToMintOverLimit);
        vm.stopPrank();
    }

    function testHealthFactorIsOkAfterMint() public depositedCollateral {
        uint256 amountToMintUnderLimit = 5_000e18;
        // 10 ETH x $2000 = $20,000 kolaterala
        // $20,000 x 50% = $10,000 max DSC
        // HF = ($10,000e18 * 1e18) / 5_000e18 = 2e18
        uint256 expectedHealthFactor = 2e18;

        vm.startPrank(user);
        engine.mintDsc(amountToMintUnderLimit);

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(user);
        uint256 collateralAdjusted = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100;
        uint256 actualHealthFactor = (collateralAdjusted * 1e18) / totalDscMinted;

        assertEq(totalDscMinted, amountToMintUnderLimit);
        assertGe(actualHealthFactor, MIN_HEALTH_FACTOR);
        assertEq(actualHealthFactor, expectedHealthFactor);
        vm.stopPrank();
    }

    function testRevertIfAmountIsZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        engine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateral() public depositedCollateral {
        vm.startPrank(user);
        engine.redeemCollateral(weth, amountCollateral);
        assertEq(ERC20Mock(weth).balanceOf(user), STARTING_USER_BALANCE);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(user);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 0);
        vm.stopPrank();
    }

    function testRevertIfHealthFactorIsUnderMin() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, 0));
        engine.redeemCollateral(weth, amountCollateral);
        vm.stopPrank();
    }

    function testLiquidateRevertsIfHealthFactorOk() public depositedCollateralAndMintedDsc {
        address liquidator = makeAddr("liquidator");
        vm.startPrank(liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOk.selector);
        engine.liquidate(weth, user, amountToMint);
        vm.stopPrank();
    }

    function testLiquidate() public depositedCollateralAndMintedDsc {
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(18e8); // cijena pada na $18

        // liquidator treba puno WETH jer je cijena ETH pala na $18
        // 200 ETH × $18 = $3600 kolaterala, max DSC = $1800 — dovoljno za pokriti 100 DSC duga
        uint256 liquidatorCollateral = 200 ether;
        address liquidator = makeAddr("liquidator");
        ERC20Mock(weth).mint(liquidator, liquidatorCollateral);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), liquidatorCollateral);
        engine.depositCollateral(weth, liquidatorCollateral);
        engine.mintDsc(amountToMint);
        dsc.approve(address(engine), amountToMint);
        engine.liquidate(weth, user, amountToMint);
        vm.stopPrank();

        // liquidator je potrošio DSC (amountToMint) i dobio kolateral + 10% bonus
        // user: DSC dug je pokriven, s_DscMinted = 0
        (uint256 totalDscMinted,) = engine.getAccountInformation(user);
        assertEq(totalDscMinted, 0);
        // liquidator je potrošio sve DSC tokene za likvidaciju
        assertEq(dsc.balanceOf(liquidator), 0);
    }

    function testRedeemCollateralForDsc() public depositedCollateralAndMintedDsc {
        vm.startPrank(user);
        dsc.approve(address(engine), amountToMint);
        engine.redeemCollateralForDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        assertEq(dsc.balanceOf(user), 0);
        assertEq(ERC20Mock(weth).balanceOf(user), STARTING_USER_BALANCE);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(user);
        assertEq(totalDscMinted, 0);
        assertEq(collateralValueInUsd, 0);
    }

    function testDepositCollateralAndMintDsc() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(engine), amountCollateral);
        engine.depositCollateralAndMintDsc(weth, amountCollateral, amountToMint);
        vm.stopPrank();
        assertEq(dsc.balanceOf(user), amountToMint);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(user);
        assertEq(totalDscMinted, amountToMint);
        assertEq(collateralValueInUsd, 20_000e18);
    }

    function testPartialLiquidation() public depositedCollateralAndMintedDsc {
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(18e8); // cijena pada na $18
        address liquidator = makeAddr("liquidator");
        ERC20Mock(weth).mint(liquidator, 200 ether);
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(engine), 200 ether);
        engine.depositCollateral(weth, 200 ether);
        uint256 debtToCover = 50 ether;
        engine.mintDsc(amountToMint);
        engine.mintDsc(debtToCover);
        dsc.approve(address(engine), debtToCover);
        engine.liquidate(weth, user, debtToCover);
        vm.stopPrank();
        (uint256 totalDscMinted,) = engine.getAccountInformation(user);
        assertEq(totalDscMinted, amountToMint - debtToCover);
        assertEq(dsc.balanceOf(liquidator), amountToMint);
    }

    function testgetAccountCollateralValue() public depositedCollateral {
        vm.startPrank(user);
        uint256 collateralValue = engine.getAccountCollateralValue(user);
        assertEq(collateralValue, 20_000e18);
        vm.stopPrank();
    }
}
