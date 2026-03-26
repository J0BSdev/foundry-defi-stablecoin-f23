//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./library/OracleLib.sol";

/// @title DSCEngine
/// @notice Core logic for the Decentralized Stable Coin (DSC): collateral deposits, DSC mint/burn, redemption, and liquidation.
/// @dev Uses Chainlink price feeds (via `OracleLib` stale checks on `getUsdValue`). Collateral is exogenous (e.g. WETH, WBTC). The system targets $1 per DSC via over-collateralization and health-factor checks. `LIQUIDATION_THRESHOLD` implies users need ~200% collateralization at the threshold (50% liquidation threshold in internal math).
contract DSCEngine is ReentrancyGuard {
    /// @notice Amount parameter was zero where a positive value is required.
    error DSCEngine__NeedsMoreThanZero();
    /// @notice Constructor arrays `tokenAddresses` and `priceFeedAddresses` length mismatch.
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    /// @notice Token is not configured as collateral (no price feed).
    error DSCEngine__NotAllowedToken();
    /// @notice ERC-20 `transfer` or `transferFrom` returned false.
    error DSCEngine__TransferFailed();
    /// @notice Operation would leave `user` with health factor below `MIN_HEALTH_FACTOR`.
    /// @param healthFactor The health factor after the attempted operation.
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    /// @notice `DecentralizedStableCoin.mint` returned false.
    error DSCEngine__MintFailed();
    /// @notice Liquidation attempted but the user is not undercollateralized.
    error DSCEngine__HealthFactorOk();
    /// @notice Liquidation did not strictly improve the user's health factor.
    error DSCEngine__HealthFactorNotImproved();
    /// @notice Burn would exceed the user's recorded DSC debt (internal accounting).
    error DSCEngine__BurnAmountExceedsBalance();

    using OracleLib for AggregatorV3Interface;

    uint256 private constant LIQUIDATION_THRESHOLD = 50; // This means you need to be 200% over-collateralized
    uint256 private constant LIQUIDATION_BONUS = 10; // This means you get assets at a 10% discount when liquidating
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    /// @notice Emitted when a user deposits collateral.
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    /// @notice Emitted when collateral is transferred out (redeem or liquidate).
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address token, uint256 amount);

    /// @dev Reverts if `amount == 0`.
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    /// @dev Reverts if `token` has no registered price feed (not a supported collateral type).
    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /// @notice Deposits collateral then mints DSC in one transaction.
    /// @param tokenCollateralAddress ERC-20 collateral token to deposit.
    /// @param amountCollateral Amount of collateral to deposit (token's native decimals).
    /// @param amountDscToMint Amount of DSC to mint (18 decimals).
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /// @notice Deposits collateral into the engine without minting DSC.
    /// @param tokenCollateralAddress Supported collateral token address.
    /// @param amountCollateral Amount to deposit.
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;

        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /// @notice Initializes collateral types and their Chainlink feeds, and wires the DSC token.
    /// @param tokenAddresses Supported collateral ERC-20 addresses (order matches `priceFeedAddresses`).
    /// @param priceFeedAddresses Chainlink `AggregatorV3Interface` per token (same length as `tokenAddresses`).
    /// @param dscAddress Deployed `DecentralizedStableCoin` contract (engine should be set as owner/minter).
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /// @notice Burns DSC from the caller then redeems collateral. Restores a safe health factor if positions were overcollateralized.
    /// @param tokenCollateralAddress Collateral token to withdraw.
    /// @param amountCollateral Amount of collateral to redeem.
    /// @param amountDscToBurn DSC amount to burn (18 decimals).
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @notice Redeems collateral to the caller without burning DSC in this call.
    /// @dev If the position remains under the minimum health factor after redemption, the call reverts. Users with DSC debt may need to burn DSC elsewhere first or use `redeemCollateralForDsc`.
    /// @param tokenCollateralAddress ERC-20 collateral token to withdraw.
    /// @param amountCollateral Amount of collateral to redeem.
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @notice Mints DSC to the caller against their existing collateral.
    /// @param amountDscToMint DSC to mint (wei, 18 decimals). Must not push the account below the minimum health factor.
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /// @notice Burns the caller's DSC held in their wallet, reducing minted debt attributed to them.
    /// @param amount DSC amount to burn (18 decimals).
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @notice Liquidates an undercollateralized position: burns the liquidator's DSC to cover debt and seizes collateral plus a bonus.
    /// @dev Reverts if the user's health factor is already >= `MIN_HEALTH_FACTOR`, or if the user's health factor does not improve, or if the liquidator ends up below minimum health factor.
    /// @param collateral Collateral token to receive from the distressed user.
    /// @param user Account to liquidate.
    /// @param debtToCover DSC debt to cover (bounded by the user's minted amount in practice).
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
        isAllowedToken(collateral)
    {
        uint256 startinUserHealthFactor = _healthFactor(user);
        if (startinUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        _redeemCollateral(user, msg.sender, collateral, tokenAmountFromDebtCovered + bonusCollateral);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startinUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @dev Returns total DSC minted to `user` and total collateral value in USD (18-decimal USD wei).
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
    }

    /// @dev Health factor = (collateral USD * threshold / 100) * 1e18 / minted DSC. Returns `type(uint256).max` if no debt.
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        if (totalDscMinted == 0) return type(uint256).max;
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /// @dev Reverts if `_healthFactor(user) < MIN_HEALTH_FACTOR` (1e18).
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    /// @dev Pulls DSC from `dscfrom`, reduces `onBehalfOf` debt, and burns tokens held by this contract.
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscfrom) private {
        s_DscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscfrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    /// @dev Updates storage and sends `amountCollateral` of `tokenCollateralAddress` from `from` to `to`.
    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /// @notice Converts a USD amount (18-decimal wei) to token amount using the latest oracle price (no stale check on this path).
    /// @param token Collateral token.
    /// @param usdAmountInWei USD value scaled by 1e18.
    /// @return Amount of `token` in its native decimals.
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }

    /// @notice Sums USD value of all collateral types deposited by `user`.
    /// @param user Account to query.
    /// @return totalCollateralValueInUSD Total collateral in USD wei (18 decimals).
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getUsdValue(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    /// @notice USD value of `amount` of `token` using stale-checked oracle data.
    /// @param token Collateral token.
    /// @param amount Token amount in native decimals.
    /// @return USD value scaled by 1e18.
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLastestData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    /// @notice Returns DSC debt and total collateral value in USD for `user`.
    /// @param user Account to query.
    /// @return totalDscMinted DSC minted against this user (18 decimals).
    /// @return collateralValueInUSD Sum of collateral in USD wei (18 decimals).
    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        (totalDscMinted, collateralValueInUSD) = _getAccountInformation(user);
    }

    /// @notice All collateral token addresses registered at deployment.
    /// @return List of supported collateral ERC-20 addresses.
    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    /// @notice Deposited balance of `token` for `user`.
    /// @param user Account.
    /// @param token Collateral token address.
    /// @return Deposited amount in token native units.
    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    /// @notice Chainlink aggregator used for `token`, or zero if not supported.
    /// @param token Collateral token.
    /// @return Price feed contract address.
    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }
}
