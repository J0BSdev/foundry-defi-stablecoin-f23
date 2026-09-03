//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";


error DSC__EngineNeedsMoreThanZero();
error Transfer__Failed();
error Mint__Failed();




contract DSCEnginePractice {

    IERC20 public weth;
    DecentralizedStableCoin public dsc;
    AggregatorV3Interface public priceFeed;


uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
uint256 private constant PRECISION = 1e18;



    mapping(address => uint256) public collateralDeposited;
    mapping(address => uint256) public debtMinted; 

    constructor(address tokenAddress , address dscAddress, address priceFeedAddress ){
    weth = IERC20(tokenAddress);
    dsc = DecentralizedStableCoin(dscAddress);
    priceFeed = AggregatorV3Interface(priceFeedAddress);
}

    function depositCollateral(uint256 amount)external{ 
         if (amount == 0 ){
       revert DSC__EngineNeedsMoreThanZero();
         }
        bool success = weth.transferFrom(msg.sender,address(this), amount);
        if (! success )
        {
    revert Transfer__Failed();}

       //we have to transfer collateral from user to protocol
        collateralDeposited[msg.sender]+= amount;
        //we have to confirm users deposit
    }



        function mintDsc(uint256 amountDscToMint)public{
            if (amountDscToMint == 0 ){
                revert DSC__EngineNeedsMoreThanZero();
            }
            
            debtMinted[msg.sender] += amountDscToMint;
    
            bool success = dsc.mint(msg.sender,amountDscToMint);
            if (!success){

            revert Mint__Failed();

                }

            }



            function getUsdValue(uint256 amount)public view returns(uint256){

           (, int256 price , , ,) = priceFeed.latestRoundData();

           return (uint256 (price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION;
                      //2000 * 1e8         1e10                   1000e18     1e18
                     



            }
              
}