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

uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
uint256 private constant PRECISION = 1e18;
uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
uint256 private constant LIQUIDATION_PRECISION = 100;
uint256 private constant MIN_HEALTH_FACTOR = 1 * PRECISION;



mapping(address token => address priceFeed) private s_priceFeeds;
mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
mapping(address user => uint256 amountDscMinted) private s_DscMinted;
address[] private s_collateralTokens;





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




function depositCollateralAndMintDsc() external{}




function depositCollateral(address tokenCollateralAddress,
uint256 amountCollateral)
external moreThanZero(amountCollateral) 
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


function redeemCollateralForDsc() external{}


function redeemCollateral() external {}

function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint)
nonReentrant{
s_DscMinted[msg.sender] += amountDscToMint;
_revertIfHealthFactorIsBroken(msg.sender);
bool minted = i_dsc.mint(msg.sender,amountDscToMint);
if (!minted){
    revert DSCEngine__MintFailed();
}

}

function burnDsc() external {}

function liquidate() external{}

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

}