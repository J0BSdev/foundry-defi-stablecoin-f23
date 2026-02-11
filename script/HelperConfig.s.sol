//SPDX-License-Identifier: MIT
 pragma solidity ^0.8.20;

 import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.t.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";



 contract HelperConfig is Script{
    struct NetworkConfig{
        address wethUsdPriceFeed;
        address wbtcUsdPriceFeed;
        address weth;
        address wbtc;
        uint256 deployerKey;
    }


    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
uint256 public DEFAULT_ANVIL_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    NetworkConfig public activeNetworkConfig;

    constructor(){
if (block.chainid == 11155111){
    activeNetworkConfig = getSepoliaEthConfig();
 } else {
    activeNetworkConfig = getorCreateAnvilEthConfig();
 }

    }

       function getSepoliaEthConfig() public view returns (NetworkConfig memory){
        return NetworkConfig({
            wethUsdPriceFeed: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeed: 0x1b44D590475cDeD6a287890a2eA3e48ADe2282c1,
            weth: 0x4200000000000000000000000000000000000006,
            wbtc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
       }

       function getorCreateAnvilEthConfig() public returns (NetworkConfig memory){
        if (activeNetworkConfig.wethUsdPriceFeed != address(0)){
            return activeNetworkConfig;
        }
        return getSepoliaEthConfig();
       }

    

       MockV3Aggregator wbtcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE
       );
    ERC20Mock wbtc = new ERC20Mock("WBTC", "WBTC", DECIMALS, INITIAL_SUPPLY);

       MockV3Aggregator wethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE
       );
    ERC20Mock weth = new ERC20Mock("WETH", "WETH", DECIMALS, INITIAL_SUPPLY);

    return NetworkConfig({
        wethUsdPriceFeed: address(wethUsdPriceFeed),
        wbtcUsdPriceFeed: address(wbtcUsdPriceFeed),
        weth: address(weth),
        wbtc: address(wbtc),
        deployerKey: DEFAULT_ANVIL_KEY
    });

 }
 }