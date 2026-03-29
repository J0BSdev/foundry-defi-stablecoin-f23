// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// -----------------------------------------------------------------------------
// Lagana vježba u stilu DSCEngine + DSC (errors, modifier, mapping, pozivi).
// Ovo je ispravljena / rješena verzija nakon vježbe (radi i kao referenca).
// -----------------------------------------------------------------------------

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/// @notice Mini DSC — samo engine smije mintati; stanje je u `balanceOf` (nije poseban ERC-20 transfer).
contract MiniStableCoin {
    error MiniStableCoin__NotEngine();

    address public immutable engine;
    mapping(address => uint256) public balanceOf;

    constructor(address engine_) {
        engine = engine_;
    }

    function mint(address to, uint256 amount) external returns (bool) {
        if (msg.sender != engine) revert MiniStableCoin__NotEngine();
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice Jedan collateral token, deposit + mint DSC.
contract MiniEngine {
    error MiniEngine__NeedsMoreThanZero();
    error MiniEngine__TransferFailed();
    error MiniEngine__NeedCollateralBeforeMint();

    MiniStableCoin public immutable i_dsc;
    IERC20 public immutable i_collateral;

    mapping(address user => uint256 amountCollateral) public s_collateralDeposited;

    constructor(address collateralToken) {
        i_collateral = IERC20(collateralToken);
        i_dsc = new MiniStableCoin(address(this));
    }

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert MiniEngine__NeedsMoreThanZero();
        _;
    }

    /// @notice Položi collateral (provjera povrata `transferFrom`).
    function depositCollateral(uint256 amountCollateral) external moreThanZero(amountCollateral) {
        bool ok = i_collateral.transferFrom(msg.sender, address(this), amountCollateral);
        if (!ok) revert MiniEngine__TransferFailed();
        s_collateralDeposited[msg.sender] += amountCollateral;
    }

    /// @notice Mintaj DSC — pojednostavljeno: mora postojati collateral (u pravom DSCEngine ide cijena + health factor).
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) {
        if (s_collateralDeposited[msg.sender] == 0) revert MiniEngine__NeedCollateralBeforeMint();
        i_dsc.mint(msg.sender, amountDscToMint);
    }
}
