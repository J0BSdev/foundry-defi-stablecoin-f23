//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;


import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";


contract DSCEnginePractice {

    IERC20 public weth;
    DecentralizedStableCoin public dsc;

    mapping(address => uint256) public collateralDeposited;
    mapping(address => uint256) public debtMInted;

}


    function depositCollateral()public payable

    depositCollateral(tokenAddress)
}
}