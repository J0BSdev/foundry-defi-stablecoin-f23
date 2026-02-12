//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { DeployDSC } from "../../../script/DeployDSC.s.sol";
import { DecentralizedStableCoin } from "../../../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../../../src/DSCEngine.sol";
import { HelperConfig } from "../../../script/HelperConfig.s.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


contract DSCEngineTest is Test {

DeployDSC public deployer;
DecentralizedStableCoin public dsc;
DSCEngine public engine;
HelperConfig public config;

address public ethUsdPriceFeed;
address public weth;
address public btcUsdPriceFeed;
address public wbtc;
uint256 public deployerKey;

uint256 public constant AMOUNT_COLLATERAL = 10 ether;
uint256 public constant STARTING_USER_BALANCE = 10 ether;

    function setUp() public {
        deployer =new DeployDSC();
        (dsc, engine, config) = deployer.run();
(ethUsdPriceFeed,btcUsdPriceFeed, wbtc, weth,) = config.activeNetworkConfig();
vm.deal(deployerKey, STARTING_USER_BALANCE);

 ERC20Mock(weth).mint(deployerKey, STARTING_USER_BALANCE);
ERC20Mock(wbtc).mint(deployerKey, STARTING_USER_BALANCE);

    }
    
address[] public tokenAddresses;
address[] public priceFeedAddresses; 



function testRevertsIfTokenLenghtDoesntMatchPriceFeed() public{
    tokenAddresses.push(weth);
    priceFeedAddresses.push(ethUsdPriceFeed);                                                
    priceFeedAddresses.push(btcUsdPriceFeed);

    vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
    new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));

}




function testGetUSdValue() public{
    uint256 ethAmount = 15e18;
    uint256 expectedUsd = 30000e18;
    uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
    assertEq(actualUsd, expectedUsd);

}



function testGetTokenAmountFromUsd() public{
    uint256 usd = 100 ether;
    uint256  expectedWeth = 0.05 ether;
    uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usd);
    assertEq(expectedWeth, actualWeth);

}




function testRevertsIfCollateralZero() public{
    vm.startPrank(deployerKey);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
    engine.getUsdValue(weth, AMOUNT_COLLATERAL);
    vm.stopPrank();
    
}
    
    
    
    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randToken = new ERC20Mock("RAN", "RAN", deployerKey , 100e18);
        vm.startPrank(deployerKey);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedToken.selector, address(randToken)));
        engine.depositCollateral(address(randToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }


modifier depositedCollateral() {
    vm.startPrank(deployerKey);
    ERC20Mock(weth).approve(address(engine), AMOUNT_COLLATERAL);
    engine.depositCollateral(weth, AMOUNT_COLLATERAL);
    vm.stopPrank();
    _;
}



function testCanDepositCollateralWithoutMinting() public depositedCollateral {
        uint256 userBalance = dsc.balanceOf(deployerKey);
        assertEq(userBalance, 0);
    }

    
    
function testCanDepositCollateralAndGetAcountInfo() public depositedCollateral{
   (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(deployerKey);
uint256 expectedTotalDscMinted = 0;
uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
assertEq(totalDscMinted, expectedTotalDscMinted);
assertEq( AMOUNT_COLLATERAL, expectedDepositAmount);


}
}