//SPDX-License-Identifier: MIT
//layout of the contract























pragma solidity ^0.8.19;


/* 
* @title DSCEngine
* @author Lovro Posel
* @notice this is the engine that manages the DSCToken and the collateral
*the system is designed to  be as  posible, and have the tokens mantain a 1 token == $1 PEG
*this stablecoin has the propetrties
* -exogenous collateral 
*=

*/
contract DSCEngine{
function depositCollsteralAndMintDsc() external{}

function depositCollateral() external {}

function redeemCollateral() external {}

function MintDsc() external{}

function redeemCollateralForDsc() external {}

function burnDsc() external {}

function liquidate() external{}

function gethealthFactor() external view {}

}