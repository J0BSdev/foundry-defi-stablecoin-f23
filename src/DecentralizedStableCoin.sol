//SPDX-License-Identifier: MIT
//layout of the contract























pragma solidity ^0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";


/*
* @title DecentralizedStableCoin
* @author Lovro Posel
*collateral : exogenous (ETH and BTC)
*Minting: algorithmic (based on collateral)
*relative stability: pegged to USD
* this is the contract meant to be governed by DSCEngine. this contract i s just the ERC20 implematation of the stablecoin system.
*/






contract DecentralizedStableCoin is ERC20Burnable,Ownable(msg.sender) {


error DecentralizedStableCoin__MustBeMoreThanZero();
error DecentralizedStableCoin__BurnAmountExceedsTheBalance();
error DecentralizedStableCoin__NotZeroAddress();


    constructor() ERC20("DecentralizedStableCoin", "DSC") {}


        function burn(uint256 amount) public override onlyOwner {
            uint256 balance = balanceOf(msg.sender);
        
            if (amount <=0){
                revert DecentralizedStableCoin__MustBeMoreThanZero();

            }

            if (balance < amount){
                revert DecentralizedStableCoin__BurnAmountExceedsTheBalance();
            }

            super.burn(amount);
    }


    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        if (to == address(0)){
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (amount <= 0){
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(to, amount);
        return true;
    }
}