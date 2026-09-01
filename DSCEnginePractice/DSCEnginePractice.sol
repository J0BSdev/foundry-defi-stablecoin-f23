//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";


error DSC__EngineNeedsMoreThanZero();


contract DSCEnginePractice {

    IERC20 public weth;
    DecentralizedStableCoin public dsc;

    mapping(address => uint256) public collateralDeposited;
    mapping(address => uint256) public debtMInted;


    function depositCollateral(uint256 amount)external{
        weth.tranferFrom(msg.sender,address(this),amount);
       //we have to transfer collateral from user to protocol
        collateralDeposited[msg.sender]+= amount;
        //we have to confirm users deposit
       if (amount == 0 )
       revert DSC__EngineNeedsMoreThanZero();  

    }
    
    
        


    }

    