//SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title DecentralizedStableCoin
/// @author Lovro Posel
/// @notice ERC-20 token for the DSC system. Minting and burning are restricted to the owner (expected to be `DSCEngine`).
/// @dev Exogenous collateral (e.g. WETH, WBTC) backs DSC off-chain in the engine; this contract is only the fungible token layer pegged to USD in design.
contract DecentralizedStableCoin is ERC20Burnable, Ownable(msg.sender) {
    /// @notice Mint or burn amount was zero or negative.
    error DecentralizedStableCoin__MustBeMoreThanZero();
    /// @notice Burn amount exceeds the owner's token balance.
    error DecentralizedStableCoin__BurnAmountExceedsTheBalance();
    /// @notice Mint target cannot be the zero address.
    error DecentralizedStableCoin__NotZeroAddress();

    /// @notice Deploys the DSC token with name "DecentralizedStableCoin" and symbol "DSC".
    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    /// @notice Destroys `amount` tokens from the caller's balance.
    /// @dev Overrides `ERC20Burnable.burn` so only the owner can burn (typically `DSCEngine` when pulling DSC for repayment/liquidation).
    /// @param amount Number of wei of DSC to burn; must be positive and not exceed balance.
    function burn(uint256 amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }

        if (balance < amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsTheBalance();
        }

        super.burn(amount);
    }

    /// @notice Mints `amount` new DSC tokens to `to`.
    /// @dev Callable only by the owner. Used by `DSCEngine` when users mint against collateral.
    /// @param to Recipient address; must not be the zero address.
    /// @param amount Amount to mint in wei; must be positive.
    /// @return success Always true if the call does not revert.
    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        if (to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        _mint(to, amount);
        return true;
    }
}
