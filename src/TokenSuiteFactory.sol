// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {GenericFactory} from "evk/GenericFactory/GenericFactory.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {LibRLP} from "solady/utils/LibRLP.sol";
import {IPerspective} from "./vendor/IPerspective.sol";
import {BasicAsset} from "./tokens/BasicAsset.sol";
import {ICreateX} from "./vendor/ICreateX.sol";

/// @notice Parameters for deploying an ERC20 token with TokenSuiteFactory.
struct ERC20Params {
    string name;
    string symbol;
    uint256 totalSupply;
}

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
    /// @param params The parameters for the ERC20 token.
    /// @param to The address to mint the initial supply of the token to.
    /// @param salt The salt for the CREATE3 deployment via CREATEX. MUST have crosschain deployment protection
    ///             and can have permissioned deploy protection. These are not enforced.
    /// @return token The address of the deployed token, always starting with 0x2718 (Leonhard will be proud).
    function deployERC20(ERC20Params memory params, address to, bytes32 salt) external returns (address token) {
        require(bytes(params.name).length < 32, NameTooLong());
        require(bytes(params.symbol).length < 32, SymbolTooLong());

        bytes memory args = abi.encode(params.name, params.symbol, to, params.totalSupply);
        // aderyn-ignore-next-line(abi-encode-packed-hash-collision)
        bytes memory initCode = abi.encodePacked(type(BasicAsset).creationCode, args);

        // The CREATEX salts we use MUST have crosschain deployment protection to mitigate this on L2s.
        token = CREATEX.deployCreate3(salt, initCode);

        require(uint160(token) >> 144 == 0x2718, NotEulaunchTokenAddress());

        emit ERC20Deployed(token, to);
    }

    /// @notice Preview the address of the ERC20 token that would be deployed with the given salt.
    /// @param salt The salt for the CREATE3 deployment via CREATEX.
    /// @return token The address of the token that would be deployed.
    function previewERC20(bytes32 salt) external view returns (address token) {
        bytes32 guardedSalt = _efficientHash({a: bytes32(block.chainid), b: salt});
        token = CREATEX.computeCreate3Address(guardedSalt);
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

    /// @notice Preview the address of the *NEXT* escrow vault that would be deployed.
    /// @return vault The address of the vault that would be deployed.
    function previewEscrowVault() external view returns (address vault) {
        uint256 nonce = GenericFactory(eVaultFactory).getProxyListLength();
        vault = LibRLP.computeAddress(eVaultFactory, nonce + 1);
    }

    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            hash := keccak256(0x00, 0x40)
        }
    }
}
