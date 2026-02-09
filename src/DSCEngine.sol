//SPDX-License-Identifier: MIT
//layout of the contract























pragma solidity ^0.8.19;


import {DecentralizedStableCoin}

 
/* 
* @title DSCEngine
* @author Lovro Posel
* @notice this is the engine that manages the DSCToken and the collateral
*the system is designed to  be as  posible, and have the tokens mantain a 1 token == $1 PEG
*this stablecoin has the propetrties
* -exogenous collateral 
*=

 */ 


contract DSCEngine is {


error DSCEngine__NeedsMoreThanZero();
error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();





mapping(address token => address priceFeed) private s_priceFeeds;



DecentralizedStableCoin

    
    
    modifier moreThanZero(uint256 amount){
    if (amount == 0){
        revert DSCEngine__NeedsMoreThanZero();
    }
    _;
}


modifier isAllowedToken(address token)




function depositCollsteralAndMintDsc() external{}




function depositCollateral(address tokenCollateralAddress,
uint256 amountCollateral)
external moreThanZero(amountCollateral){}


constructor(address[]memoryrokenAdresses,
address[] memory priceFeedAddress,
address dscAddress
){

    if(tokenAddresses.length != priceFeedAddresses.length)
    revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
}


for(uint256 i=0; i<tokenAddresses.length; i++){
    s_priceFeeds[tokenAddresses[i]]= priceFeedAddresses[i];
}

}





function redeemCollateral() external {}

function MintDsc() external{}

function redeemCollateralForDsc() external {}

function burnDsc() external {}

function liquidate() external{}

function gethealthFactor() external view {}

}