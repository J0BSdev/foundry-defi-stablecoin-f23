//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { DeployDSC } from "../../../script/DeployDSC.s.sol";
import { DecentralizedStableCoin } from "../../../src/DecentralizedStableCoin.sol";
import { DSCEngine } from "../../../src/DSCEngine.sol"; 
import { HelperConfig } from "../../../script/HelperConfig.s.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";


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
(ethUsdPriceFeed,btcUsdPriceFeed, wbtc, weth,) = helperConfig.activeNetworkConfig();

if (block.chainid == 31_337) {
vm.deal(user , STARTING_USER_BALANCE);
}

 ERC20Mock(weth).mint(user, STARTING_USER_BALANCE);
ERC20Mock(wbtc).mint(user, STARTING_USER_BALANCE);

    }

    address[] public tokenAddresses;
    address[] public feedAddresses;

function testRevertsIfTokenLenghtDoesntMatchPriceFeed() public{
    tokenAddresses.push(weth);
   feedAddresses.push(ethUsdPriceFeed);                                                
  feedAddresses.push(btcUsdPriceFeed);
  
  vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, feedAddresses, address(dsc));
}




function testGetUSdValue() public view{
    uint256 ethAmount = 15e18;
    uint256 expectedUsd = 30000e18;
    uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
    assertEq(actualUsd, expectedUsd);



  
}  



function testGetTokenAmountFromUsd() public view{
    uint256 usd = 100 ether;
    uint256  expectedWeth = 0.05 ether;
    uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usd);
    assertEq(expectedWeth, actualWeth);

}




function testRevertsIfCollateralZero() public{
    vm.startPrank(user);
    ERC20Mock(weth).approve(address(engine), amountCollateral);
    vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
    engine.getUsdValue(weth, amountCollateral);
    vm.stopPrank();
    
}
    
    
    
    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock randToken = new ERC20Mock();
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

    
    
function testCanDepositCollateralAndGetAcountInfo() public depositedCollateral{
   (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(user);
uint256 expectedTotalDscMinted = 0;
uint256 expectedDepositAmount = engine.getTokenAmountFromUsd(weth, collateralValueInUsd);
assertEq(totalDscMinted, expectedTotalDscMinted);
assertEq( amountCollateral, expectedDepositAmount);

}
}