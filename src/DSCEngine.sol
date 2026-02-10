//SPDX-License-Identifier: MIT
//layout of the contract























pragma solidity ^0.8.19;


import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/*


* @title DSCEngine
* @author Lovro Posel
* @notice this is the engine that manages the DSCToken and the collateral
*the system is designed to  be as  posible, and have the tokens mantain a 1 token == $1 PEG
*this stablecoin has the propetrties
* -exogenous collateral 
*

 */ 


contract DSCEngine is ReentrancyGuard {


error DSCEngine__NeedsMoreThanZero();
error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
error DSCEngine__NotAllowedToken();
error DSCEngine__TransferFailed();



mapping(address token => address priceFeed) private s_priceFeeds;
mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;


DecentralizedStableCoin private immutable i_dsc;



event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    
    
    modifier moreThanZero(uint256 amount){
    if (amount == 0){
        revert DSCEngine__NeedsMoreThanZero();
    }
    _;
}


modifier isAllowedToken(address token){
    if (s_priceFeeds[token] == address(0)){
        revert DSCEngine__NotAllowedToken();
    }
    _;
}




function depositCollsteralAndMintDsc() external{}




function depositCollateral(address tokenCollateralAddress,
uint256 amountCollateral)
external moreThanZero(amountCollateral) 
isAllowedToken(tokenCollateralAddress)
nonReentrant
{

    s_collateralDeposited[msg.sender][tokenCollateralAddress]
    += amountCollateral;
emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
   boll success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
   if (!success){
    revert DSCEngine__TransferFailed();
   }
}


constructor(address[]memoryrokenAdresses,
address[] memory priceFeedAddress,
address dscAddress
){

    if(tokenAddresses.length != priceFeedAddresses.length)
    revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
}

    for (uint256 i = 0; i < tokenAddresses.length; i++) {
        s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
    }

i_dsc = DecentralizedStableCoin(dscAddress);

}





function redeemCollateral() external {}

function MintDsc() external{}

function redeemCollateralForDsc() external {}

function burnDsc() external {}

function liquidate() external{}

function gethealthFactor() external view {}

}