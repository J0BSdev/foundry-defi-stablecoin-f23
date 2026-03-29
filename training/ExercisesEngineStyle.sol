// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// -----------------------------------------------------------------------------
// Lagane vježbe u stilu DSCEngine + DecentralizedStableCoin (errors, modifieri,
// mapping po useru/tokenu, deposit + mint). Namjerno ima bugova — pronađi ih.
// -----------------------------------------------------------------------------

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @notice Mini DSC: mint/burn samo od strane “enginea” (owner = engine).
contract MiniStableCoin {
    error MiniStableCoin__NotEngine();
    error MiniStableCoin__ZeroAddress();
    error MiniStableCoin__MustBeMoreThanZero();

    address public engine;
    mapping(address => uint256) public balanceOf;

    constructor() {
        engine = msg.sender;
    }

    function mint(address to, uint256 amount) external returns (bool) {
        if (msg.sender != engine) revert MiniStableCoin__NotEngine();
        if (to == address(0)) revert MiniStableCoin__ZeroAddress();
        if (amount == 0) revert MiniStableCoin__MustBeMoreThanZero();
        balanceOf[to] += amount;
        return true;
    }

    function burnFrom(address from, uint256 amount) external {
        if (msg.sender != engine) revert MiniStableCoin__NotEngine();
        if (amount == 0) revert MiniStableCoin__MustBeMoreThanZero();
        balanceOf[from] -= amount;
    }
}

/// @notice Pojednostavljeni engine: collateral u ERC-20, mint mini DSC-a.
contract MiniEngine {
    error MiniEngine__NeedsMoreThanZero();
    error MiniEngine__NotAllowedToken();
    error MiniEngine__TransferFailed();

    MiniStableCoin public immutable i_dsc;

    mapping(address token => bool allowed) private s_allowedCollateral;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 dscMinted) private s_dscMinted;

    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event DscMinted(address indexed user, uint256 amount);

    constructor(address dscAddress) {
        i_dsc = MiniStableCoin(dscAddress);
    }

    /// @dev Dodaj collateral token u whitelist (u praksi kao u constructoru / admin).
    function addCollateralToken(address token) external {
        s_allowedCollateral[token] = true;
    }

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) revert MiniEngine__NeedsMoreThanZero();
        _;
    }

    modifier isAllowedToken(address token) {
        if (!s_allowedCollateral[token]) revert MiniEngine__NotAllowedToken();
        _;
    }

    /// @notice Položi collateral (transferFrom u engine).
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
    }

    /// @notice Mintaj DSC korisniku (pojednostavljen model — bez health factora).
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) {
        s_dscMinted[msg.sender] += amountDscToMint;
        i_dsc.mint(msg.sender, amountDscToMint);
        emit DscMinted(msg.sender, amountDscToMint);
    }

    /// @notice Jedan call kao `depositCollateralAndMintDsc` u tvom engineu.
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint)
        external
    {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /// @notice Vrati DSC u sustav (engine spaljuje s user računa).
    function burnDsc(uint256 amount) external moreThanZero(amount) {
        s_dscMinted[msg.sender] -= amount;
        i_dsc.burnFrom(msg.sender, amount);
    }
}
