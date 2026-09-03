//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


error DSC__EngineNeedsMoreThanZero();
error Transfer__Failed();
error Mint__Failed();


contract DSCEnginePractice {

    IERC20 public weth;
    DecentralizedStableCoin public dsc;

    mapping(address => uint256) public collateralDeposited;
    mapping(address => uint256) public debtMinted; 

    constructor(address tokenAddress , address dscAddress){
    weth = IERC20(tokenAddress);
    dsc = DecentralizedStableCoin(dscAddress);
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




}