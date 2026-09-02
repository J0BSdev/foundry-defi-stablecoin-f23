//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract DSCEnginePractice is ERC20{

error DSC__EngineNeedsMoreThanZero(); 


    mapping(address => uint256) public collateralDeposited;
    mapping(address => uint256) public debtMInted;

    constructor()ERC20("DSCEngine" , "DSC"){}

    function depositCollateral(uint256 amount)external{ 
         if (amount == 0 )
       revert DSC__EngineNeedsMoreThanZero();  
        weth.tranferFrom(msg.sender,address(this),amount);
        bool success = weth.tranferFrom(msg.sender,address(this),amount);
       //we have to transfer collateral from user to protocol
        collateralDeposited[msg.sender]+= amount;
        //we have to confirm users deposit
     
    }
    
    
        


    }

    