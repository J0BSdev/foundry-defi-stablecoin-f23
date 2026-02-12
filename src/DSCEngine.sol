//SPDX-License-Identifier: MIT
//layout of the contract























pragma solidity ^0.8.19;


import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";




/*
* @titl
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
error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
error DSCEngine__MintFailed();
error DSCEngine__HealthFactorOk();
error DSCEngine__HealthFactorNotImproved();



uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
uint256 private constant PRECISION = 1e18;
uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
uint256 private constant LIQUIDATION_PRECISION = 100;
uint256 private constant MIN_HEALTH_FACTOR = 1e18;
uint256 private constant LIQUIDATION_BONUS = 10;



mapping(address token => address priceFeed) private s_priceFeeds;
mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
mapping(address user => uint256 amountDscMinted) private s_DscMinted;
address[] private s_collateralTokens;





DecentralizedStableCoin private immutable i_dsc;



event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);
    
    
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




function depositCollateralAndMintDsc(address tokenCollateralAddress,
uint256 amountCollateral, 
uint256 amountDscToMint) external{
    depositCollateral(tokenCollateralAddress, amountCollateral);
    mintDsc(amountDscToMint);
}




function depositCollateral(address tokenCollateralAddress,
uint256 amountCollateral)
public moreThanZero(amountCollateral) 
isAllowedToken(tokenCollateralAddress)
nonReentrant
{

    s_collateralDeposited[msg.sender][tokenCollateralAddress]
    += amountCollateral;
emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
   bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
   if (!success){
    revert DSCEngine__TransferFailed();
   }
}


constructor(
address[] memory tokenAddresses,
address[] memory priceFeedAddresses,
address dscAddress
){

    if(tokenAddresses.length != priceFeedAddresses.length) {
    revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
}

    for (uint256 i = 0; i < tokenAddresses.length; i++) {
        s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        s_collateralTokens.push(tokenAddresses[i]);
    }

i_dsc = DecentralizedStableCoin(dscAddress);

}


function redeemCollateralForDsc(address tokenCollateralAddress, 
uint256 amountCollateral, 
uint256 amountDscToBurn) public moreThanZero(amountCollateral) 
moreThanZero(amountDscToBurn) nonReentrant {
}


function redeemCollateral(address tokenCollateralAddress, 
uint256 amountCollateral) external moreThanZero(amountCollateral) nonReentrant {

_redeemCollateral( msg.sender, msg.sender, tokenCollateralAddress, amountCollateral );
_revertIfHealthFactorIsBroken(msg.sender);

}





function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint)
nonReentrant{
s_DscMinted[msg.sender] += amountDscToMint;
_revertIfHealthFactorIsBroken(msg.sender);
bool minted = i_dsc.mint(msg.sender,amountDscToMint);
if (!minted){
    revert DSCEngine__MintFailed();
}

}

function burnDsc(uint256 amount) public moreThanZero(amount) {
_burnDsc(amount, msg.sender, msg.sender);
_revertIfHealthFactorIsBroken(msg.sender);

}

function liquidate(address collateral,address user,uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant(){

uint256 startinUserHealthFactor = _healthFactor(user);
if (startinUserHealthFactor >= MIN_HEALTH_FACTOR){
    revert DSCEngine__HealthFactorOk();
}
uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
uint256 bonucCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonucCollateral;


_redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
_burnDsc(debtToCover, user, msg.sender);

uint256 endingUserHealthFactor = _healthFactor(user);
if (endingUserHealthFactor <= startinUserHealthFactor){
    revert DSCEngine__HealthFactorNotImproved();

}
_revertIfHealthFactorIsBroken(msg.sender);
}






function getHealthFactor() external view {}

function _getAccountInformation(address user) private view returns 
(uint256 totalDscMinted, uint256 collateralValueInUSD) {

    totalDscMinted = s_DscMinted[user];
    collateralValueInUSD = getAccountCollateralValue(user);

}
function _healthFactor(address user) private view returns (uint256) {
(uint256 totalDscMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) /
 LIQUIDATION_PRECISION;
 //return  (collateralValueInUSD / totalDscMinted) ;
 return (collateralAdjustedForThreshold * PRECISION / totalDscMinted);
}


function _revertIfHealthFactorIsBroken(address user) internal view {
uint256 userHealthFactor = _healthFactor(user);
if (userHealthFactor < MIN_HEALTH_FACTOR) {
revert DSCEngine__BreaksHealthFactor(userHealthFactor);
    }
}

function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscfrom) private{
   s_DscMinted[onBehalfOf] -= amountDscToBurn;
bool success = i_dsc.transferFrom(dscfrom, address(this), amountDscToBurn);
if (!success){
    revert DSCEngine__TransferFailed();
}
i_dsc.burn(amountDscToBurn); 





}




function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral) private{



s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
if (!success){
    revert DSCEngine__TransferFailed();

}
}
function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
    AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
    (, int256 price, , , ) = priceFeed.latestRoundData();
    return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
}





function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {


    for (uint256 i = 0; i < s_collateralTokens.length; i++) {
        address token = s_collateralTokens[i];
        uint256 amount = s_collateralDeposited[user][token];
        totalCollateralValueInUSD += getUsdValue(token, amount);
    }
    return totalCollateralValueInUSD;
} 



function getUsdValue(address token, uint256 amount) public view returns (uint256) {

    AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
    (, int256 price, , , ) = priceFeed.latestRoundData();
    return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;

}
function getAccountInformation(address user) external view returns (uint256 totalDscMinted, uint256 collateralValueInUSD) {
    (totalDscMinted, collateralValueInUSD) = _getAccountInformation(user);

}
}