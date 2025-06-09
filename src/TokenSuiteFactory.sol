// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {GenericFactory} from "evk/GenericFactory/GenericFactory.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IPerspective} from "./vendor/IPerspective.sol";
import {BasicAsset} from "./tokens/BasicAsset.sol";
import {ICreateX} from "./vendor/ICreateX.sol";

/// @title TokenSuiteFactory
/// @notice A factory for deploying ERC20 and basic "escrow vaults" to hold tokens.
/// @dev The escrow vaults are basic EVaults without borrowing or lending features.
contract TokenSuiteFactory {
    ICreateX public constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
    address public immutable eVaultFactory;
    address public immutable perspective;

    error NotEulaunchTokenAddress();
    error NameTooLong();
    error SymbolTooLong();
    error InvalidGenericFactory();
    error InvalidEscrowedCollateralPerspective();

    event ERC20Deployed(address indexed token, address indexed to);
    event EscrowVaultDeployed(address indexed vault, address indexed underlyingAsset);

    constructor(address _eVaultFactory, address _perspective) {
        require(_eVaultFactory != address(0), InvalidGenericFactory());
        require(_perspective != address(0), InvalidEscrowedCollateralPerspective());

        eVaultFactory = _eVaultFactory;
        perspective = _perspective;
    }

    /// @notice Deterministically deploys a standard immutable ERC20 token.
    /// @dev The CREATEX factory is used to deploy the token to deterministic address.
    /// @param name The name of the token.
    /// @param symbol The symbol of the token.
    /// @param to The address to mint the initial supply of the token to.
    /// @param totalSupply The total supply of the token.
    /// @param salt The salt for the CREATE3 deployment via CREATEX. MUST have crosschain deployment protection
    ///             and can have permissioned deploy protection. These are not enforced.
    /// @return token The address of the deployed token, always starting with 0x2718 (Leonhard will be proud).
    function deployERC20(string memory name, string memory symbol, address to, uint256 totalSupply, bytes32 salt)
        external
        returns (address token)
    {
        require(bytes(name).length < 32, NameTooLong());
        require(bytes(symbol).length < 32, SymbolTooLong());

        bytes memory args = abi.encode(name, symbol, to, totalSupply);
        bytes memory initCode = abi.encodePacked(type(BasicAsset).creationCode, args);

        // The CREATEX salts we use MUST have crosschain deployment protection to mitigate this on L2s.
        token = CREATEX.deployCreate3(salt, initCode);

        require(uint160(token) >> 144 == 0x2718, NotEulaunchTokenAddress());

        emit ERC20Deployed(token, to);
    }

    /// @notice Deploy an escrow vault for a given underlying asset.
    /// @dev The escrow vault is a simple vault that holds the underlying asset and does not allow borrowing.
    /// @param underlyingAsset The address of the underlying asset.
    /// @return vault The address of the deployed vault.
    function deployEscrowVault(address underlyingAsset) external returns (address vault) {
        bytes memory initData = abi.encodePacked(underlyingAsset, address(0), address(0));
        vault = GenericFactory(eVaultFactory).createProxy(address(0), true, initData);
        IEVault(vault).setHookConfig(address(0), 0);
        IEVault(vault).setGovernorAdmin(address(0));

        IPerspective(perspective).perspectiveVerify(vault, true);

        emit EscrowVaultDeployed(vault, underlyingAsset);
    }
}
