//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";


error DSC__EngineNeedsMoreThanZero();


contract DSCEnginePractice {

    IERC20 public weth;
    DecentralizedStableCoin public dsc;

    mapping(address => uint256) public collateralDeposited;
    mapping(address => uint256) public debtMInted;

    constructor(WethAddress , DscAddress){
    weth = ERC20(WethAddress);
    dsc = DecentralizedStableCoin(DscAddress);
}

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