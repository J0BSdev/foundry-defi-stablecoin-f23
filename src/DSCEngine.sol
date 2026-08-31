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
    uint256 private constant LIQUIDATION_PRECISION = 100; //koristi se za postotke cijeli broj
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; //ako padne ispod, likvidacija
    uint256 private constant PRECISION = 1e18; // osnovna preciznost za sve izracune
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; //zbog toga sto chainlink daje 8 decimala. a mi trebamo 18,dodamo 10 da bi dobili 18
    uint256 private constant FEED_PRECISION = 1e8; //chainlink price feed precision

    mapping(address token => address priceFeed) private s_priceFeeds; //za svaki token imas  njegov price feed ,za izracun collaterala(mapping sprema podatke po useru/tokenu )
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited; //koliko je user deponirao po tokenu
    mapping(address user => uint256 amountDscMinted) private s_DscMinted; //koliko je user duzan(mintao DSC),za health factor
    address[] private s_collateralTokens; //lista svih allowed tokena,za iteraciju (npr. total collateral)

    DecentralizedStableCoin private immutable i_dsc; //reference na DSC token,immutable =, postavi se jednom i vise ne mijenja,u bytecode, gas optimizacija i sigurnije

    /// @notice Emitted when a user deposits collateral.
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount); //logira deposit,za frontend i indexing
    /// @notice Emitted when collateral is transferred out (redeem or liquidate).
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address token, uint256 amount); //logira withdrawl/liquidation,za frontend i indexing,audit trail

    /// @dev Reverts if `amount == 0`.
    modifier moreThanZero(uint256 amount) {
        //check(CEI prvi korak) ne dopusta input 0
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    /// @dev Reverts if `token` has no registered price feed (not a supported collateral type).
    modifier isAllowedToken(address token) {
        // check;access + validation, provjerava  jeli token allowed,ima li price feed(modifier je ponovljeni sigurnosni check prije funkcije)
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
        //prvo deponiramo collaterala
        mintDsc(amountDscToMint);
        //zatim mintamo DSC
    }

    /// @notice Deposits collateral into the engine without minting DSC.
    /// @param tokenCollateralAddress Supported collateral token address.
    /// @param amountCollateral Amount to deposit.
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) ///koji collateral token user deponira,i koliko tog tokena user deponira
        public
        moreThanZero(amountCollateral) /// provjerava da amountCollateral !=0 (CHECK)
        isAllowedToken(tokenCollateralAddress) ///provjerava da je token whitelistan i ima price feed (CHECK)
        nonReentrant ///blokira reentrancy napad na ovu funkciju

    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        //povecava zapis koliko je user isplatio tog tokena(EFFECTS)

        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        //emitira log da se dogodio deposit,za frontend i indexing,audit trail
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral); //transferira tokena sa user accounta na DSCEngine kontrakt,
        if (!success) {
            //transferFrom osigurava da je kontrakt stvarno dobio tokene(INTERACTION)

            revert DSCEngine__TransferFailed(); //revertamo ako transfer ne uspije(ERROR,post-interaction validation)
        }
    }

    /// @notice Initializes collateral types and their Chainlink feeds, and wires the DSC token.
    /// @param tokenAddresses Supported collateral ERC-20 addresses (order matches `priceFeedAddresses`).
    /// @param priceFeedAddresses Chainlink `AggregatorV3Interface` per token (same length as `tokenAddresses`).
    /// @param dscAddress Deployed `DecentralizedStableCoin` contract (engine should be set as owner/minter).

    //lista svih allowed tokena,za iteraciju (npr. total collateral), lista svih Chainlink price feedova, adresa tvog stablecoin kontrakta
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        //constructor se izvrava samo jednom,pri deploymentu kontrakta
        if (tokenAddresses.length != priceFeedAddresses.length) { 
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
            //CHECK: svaki token mora imati price feed,a price feed mora biti validan(chainlink)
        }

        // prolazi kroz svaki pair od token i price feed
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i]; // i = brojac(index),(koji broj u listi trenutno gleda)
            //EFFECTS: povezuje token s odgovarajucim Chainlink feedom
            s_collateralTokens.push(tokenAddresses[i]);
            //EFFECTS: sprema sve allowed collateral tokene u array za kasniju iteraciju
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
        //EFFECTS : sprema adresu DSC kontrakta u immutable varijablu i_dsc
    }

    /// @notice Burns DSC from the caller then redeems collateral. Restores a safe health factor if positions were overcollateralized.
    /// @param tokenCollateralAddress Collateral token to withdraw.
    /// @param amountCollateral Amount of collateral to redeem.
    /// @param amountDscToBurn DSC amount to burn (18 decimals).

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress) ///modifier (CHECK)
        ///modifier (CHECK)

    {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        //EFFECTS + INTERACTION: smanjuje debt i burna DSC korisnika
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        //EFFECTS + INTERACTION: smanjuje collateral u stateu i vraca tokene korisniku
        _revertIfHealthFactorIsBroken(msg.sender);
        //POST-CHECK: osigurava da je user i dalje dovoljno overcollateralized(health factor je ok)
    }

    /// @notice Redeems collateral to the caller without burning DSC in this call.
    /// @dev If the position remains under the minimum health factor after redemption, the call reverts. Users with DSC debt may need to burn DSC elsewhere first or use `redeemCollateralForDsc`.
    /// @param tokenCollateralAddress ERC-20 collateral token to withdraw.
    /// @param amountCollateral Amount of collateral to redeem.

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral) ///modifier (CHECK)
        nonReentrant ///blokira reentrancy napad na ovu funkciju
        isAllowedToken(tokenCollateralAddress) ///modifier (CHECK)

    {
        //1. msg.sender = od koga se collateral skida , 2. msg.sender = kome se collateral salje
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        ///EFFECTS + INTERACTION: smanjuje collateral u stateu i vraca tokene korisniku

        _revertIfHealthFactorIsBroken(msg.sender);
        ///POST-CHECK: osigurava da korisnik nakoj svega ostaje solventan(health factor je ok)
    }

    /// @notice Mints DSC to the caller against their existing collateral.
    /// @param amountDscToMint DSC to mint (wei, 18 decimals). Must not push the account below the minimum health factor.
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        //EFFECTS : povecava userov dug prije health factor checka
        _revertIfHealthFactorIsBroken(msg.sender);
        //CHECK: nakon novog duga user mora ostati iznad min health factora
        bool minted = i_dsc.mint(msg.sender, amountDscToMint); // boll je true ili false , da ili ne,da li je mintanje uspjesno ili ne
        //INTERACTION: mintanje DSC token korisniku
        if (!minted) {
            revert DSCEngine__MintFailed();
            //SAFETY: revertamo ako mintanje ne uspije(ERROR,post-interaction validation)
        }
    }

    /// @notice Burns the caller's DSC held in their wallet, reducing minted debt attributed to them.
    /// @param amount DSC amount to burn (18 decimals).

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        //EFFECTS + INTERACTION: spaljuje DSC i smanjuje debt usera
        _revertIfHealthFactorIsBroken(msg.sender);
        // POST-CHECK: osigurava da je user i dalje dovoljno overcollateralized(health factor je ok)
    }

    /// @notice Liquidates an undercollateralized position: burns the liquidator's DSC to cover debt and seizes collateral plus a bonus.
    /// @dev Reverts if the user's health factor is already >= `MIN_HEALTH_FACTOR`, or if the user's health factor does not improve, or if the liquidator ends up below minimum health factor.
    /// @param collateral Collateral token to receive from the distressed user.
    /// @param user Account to liquidate.
    /// @param debtToCover DSC debt to cover (bounded by the user's minted amount in practice).

    function liquidate(address collateral, address user, uint256 debtToCover) /// likvidator vraca tudi dug --> dobiva njihov collateral + bonus
        external
        moreThanZero(debtToCover) /// modifier, dug koji pokrivas mora biti > 0 (CHECK)
        nonReentrant ///blokira reentrancy napad na ovu funkciju
        isAllowedToken(collateral) ///modifier, collateral mora biti allowed token (CHECK)

    {
        uint256 startinUserHealthFactor = _healthFactor(user);
        //CHECK: uzima trenutni health factor usera prije likvidacije
        if (startinUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
            //CHECK: user je jos uvijek safe, NE smije se likvidirati
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        //CALCULATION: koliko collateral tokena vrijedi ovaj debt u USD

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        //CALCULATION: dodatni bonus za likvidatora (npr. +10%)

        _redeemCollateral(user, msg.sender, collateral, tokenAmountFromDebtCovered + bonusCollateral);
        //EFFECT + INTERACTION: uzima collateral od user-a i salje likvidatoru

        _burnDsc(debtToCover, user, msg.sender);
        //EFFECT + INTERACTION:likvidator placa DSC --> userov dug se smanjuje

        uint256 endingUserHealthFactor = _healthFactor(user);
        //CHECK: novi health factor nakon likvidacije
        if (endingUserHealthFactor <= startinUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
            //CHECK: likvidcija mora poboljsati stanje usera
        }
        _revertIfHealthFactorIsBroken(msg.sender);
        //FINAL - CHECK: likvidator ne smije zavrsiti u losem stanju
    }

    /// @dev Returns total DSC minted to `user` and total collateral value in USD (18-decimal USD wei).
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUSD)
    {
        totalDscMinted = s_DscMinted[user];
        //CALCULATION: koliko DSC user duguje
        collateralValueInUSD = getAccountCollateralValue(user);
        //CALCULATION: ukupna vrijednost collaterala usera u USD
    }

    /// @dev Health factor = (collateral USD * threshold / 100) * 1e18 / minted DSC. Returns `type(uint256).max` if no debt.
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        //READ: uzima debt + collateral vrijednost
        if (totalDscMinted == 0) return type(uint256).max;
        //EDGE CASE: ako nema duga --> uvijek safe(infinite health), da nebi doslo do dijeljenja s 0

        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        //CALCULATION: smanjuje collateral (npr. 80%) za sigurnosni buffer

        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
        //FINAL CALCULATION: health factor = collateral / debt
    }

    /// @dev Reverts if `_healthFactor(user) < MIN_HEALTH_FACTOR` (1e18).
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        //READ: racuna health factor usera
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
            //CHECK: ako user padne ispod min --> revert(rollback svega)
        }
    }

    /// @dev Pulls DSC from `dscfrom`, reduces `onBehalfOf` debt, and burns tokens held by this contract.
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscfrom) private {
        s_DscMinted[onBehalfOf] -= amountDscToBurn;
        //EFFECTS: smanjuje debt usera u storage-u
        bool success = i_dsc.transferFrom(dscfrom, address(this), amountDscToBurn);
        //INTERACTION: transferira DSC od korisnika (ili likvidatora)na DSCEngine kontrakt                       // uzima DSC --> smanjuje dug --> unistava token //
        if (!success) {
            revert DSCEngine__TransferFailed();
            //CHECK: mora uspjeti transfer,inace rollback
        }
        i_dsc.burn(amountDscToBurn);
        //INTERACTION: spaljuje DSC --> smanjuje ukupni supply
    }

    /// @dev Updates storage and sends `amountCollateral` of `tokenCollateralAddress` from `from` to `to`.
    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        //EFFECTS: smanjuje collateral usera u storage-u
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        //LOG: emitira log da se dogodio redeem,za frontend i indexing,audit trail
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral); // smanji zapis --> posalji token //
        //INTERACTION: salje token iz kontrakta korisniku
        if (!success) {
            revert DSCEngine__TransferFailed();
            //CHECK: mora uspjeti transfer,inace rollback
        }
    }

    /// @notice Converts a USD amount (18-decimal wei) to token amount using the latest oracle price (no stale check on this path).
    /// @param token Collateral token.
    /// @param usdAmountInWei USD value scaled by 1e18.
    /// @return Amount of `token` in its native decimals.
    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        //READ: uzima price feed za token (npr. ETH/USD)
        (, int256 price,,,) = priceFeed.latestRoundData();
        //READ: dohvaca cijenu iz Chainlinka (npr. 2000$)
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
        //CALCULATION:
        // pretvara USD --> koliko tokena to vrijedi (npr. 1000$ --> 0.0005 ETH)
    }

    /// @notice Sums USD value of all collateral types deposited by `user`.
    /// @param user Account to query.
    /// @return totalCollateralValueInUSD Total collateral in USD wei (18 decimals).
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            //LOOP: prolazi kroz sve allowed collateral tokene
            address token = s_collateralTokens[i];
            //READ: uzima adresu tokena na indexu i
            uint256 amount = s_collateralDeposited[user][token]; // prodi sve tokene --> izracunaj vrijednost --> zbroji ukupno //
            //READ: koliko user ima tog tokena
            totalCollateralValueInUSD += getUsdValue(token, amount);
            //CALCULATION: pretvara taj token u USD i zbraja ukupno
        }
        return totalCollateralValueInUSD;
        //RETURN: ukupna vrijednost collaterala usera u USD
    }

    /// @notice USD value of `amount` of `token` using stale-checked oracle data.
    /// @param token Collateral token.
    /// @param amount Token amount in native decimals.
    /// @return USD value scaled by 1e18.
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        //READ: uzima Chainlink oracle za taj token
        (, int256 price,,,) = priceFeed.staleCheckLastestData(); // token amount --> USD vrijednost //
        //READ: dohvaca cijenu (npr. 2000$)
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
        //CALCULATION: pretvara amunt tokena u USD (npr. 0.0005 ETH --> 1000$)
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
        (totalDscMinted, collateralValueInUSD) = _getAccountInformation(user); // koliko duguje + koliko ima collaterala //
        // WRAPPER: samo vraca podatke iz interne funkcije
    }

    /// @notice All collateral token addresses registered at deployment.
    /// @return List of supported collateral ERC-20 addresses.
    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
        //RETURN: vraca sve allowed collateral tokene
    }

    /// @notice Deposited balance of `token` for `user`.
    /// @param user Account.
    /// @param token Collateral token address.
    /// @return Deposited amount in token native units.
    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
        //STORAGE READ: vraca koliko user ima tog tokena
    }

    /// @notice Chainlink aggregator used for `token`, or zero if not supported.
    /// @param token Collateral token.
    /// @return Price feed contract address.
    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
        //STORAGE READ: vraca price feed za taj token
    }
}
