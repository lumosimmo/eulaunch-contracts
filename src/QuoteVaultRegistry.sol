// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {Ownable} from "solady/auth/Ownable.sol";
import {EulerSwapFactory} from "euler-swap/src/EulerSwapFactory.sol";
import {GenericFactory} from "evk/GenericFactory/GenericFactory.sol";
import {EVault} from "euler-vault-kit/src/EVault/EVault.sol";

/// @title QuoteVaultRegistry
/// @notice A registry for associating quote tokens with their corresponding EVaults.
/// @dev This contract allows the owner to set, remove, and retrieve EVault addresses that
///      are designated as quote vaults for specific underlying tokens. The validity of the
///      vault is checked upon setting. Each token can only have one vault associated with it.
contract QuoteVaultRegistry is Ownable {
    address public immutable eulerSwapFactory;
    mapping(address token => address vault) public quoteVaults;

    error VaultDoesNotMatchToken();

    event QuoteVaultSet(address indexed token, address indexed vault);
    event QuoteVaultRemoved(address indexed token);

    constructor(address _eulerSwapFactory) {
        eulerSwapFactory = _eulerSwapFactory;
        _initializeOwner(msg.sender);
    }

    /// @dev Internal function to validate a vault, revert if invalid.
    /// @param token The address of the token for which the vault is being checked.
    /// @param vault The address of the EVault to check.
    function _checkVault(address token, address vault) internal view {
        address evkFactory = EulerSwapFactory(eulerSwapFactory).evkFactory();
        require(GenericFactory(evkFactory).isProxy(vault), EulerSwapFactory.InvalidVaultImplementation());
        address asset = EVault(vault).asset();
        require(asset == token, VaultDoesNotMatchToken());
    }

    /// @notice Sets or updates the quote vault for a given token.
    /// @dev Can only be called by the owner.
    /// @param token The address of the token.
    /// @param vault The address of the EVault to be set as the quote vault for the token.
    function setQuoteVault(address token, address vault) external onlyOwner {
        _checkVault(token, vault);
        quoteVaults[token] = vault;
        emit QuoteVaultSet(token, vault);
    }

    /// @notice Removes the quote vault association for a given token.
    /// @dev Can only be called by the owner.
    /// @param token The address of the token whose quote vault association is to be removed.
    function removeQuoteVault(address token) external onlyOwner {
        delete quoteVaults[token];
        emit QuoteVaultRemoved(token);
    }

    /// @notice Retrieves the vault address for a given quote token.
    /// @param token The address of the token.
    /// @return The address of the quote vault associated with the token, or address(0) if none is set.
    function getQuoteVault(address token) external view returns (address) {
        return quoteVaults[token];
    }
}
