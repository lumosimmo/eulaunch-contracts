// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {EVault} from "euler-vault-kit/src/EVault/EVault.sol";
import {BasicAsset} from "./tokens/BasicAsset.sol";
import {ICreateX} from "./vendor/ICreateX.sol";

/// @title TokenSuiteFactory
/// @notice A factory for deploying ERC20 and basic EVaults to hold tokens for EulerSwap.
/// @dev This factory deploys basic EVaults without borrowing or lending features.
contract TokenSuiteFactory {
    ICreateX public constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
    address public immutable eulerSwapFactory;

    error NotEulaunchTokenAddress();

    event ERC20Deployed(address indexed token, address indexed to);

    constructor(address _eulerSwapFactory) {
        eulerSwapFactory = _eulerSwapFactory;
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
        bytes memory args = abi.encode(name, symbol, to, totalSupply);
        bytes memory initCode = abi.encodePacked(type(BasicAsset).creationCode, args);

        // The CREATEX salts we use MUST have crosschain deployment protection to mitigate this on L2s.
        token = CREATEX.deployCreate3(salt, initCode);

        require(uint160(token) >> 144 == 0x2718, NotEulaunchTokenAddress());

        emit ERC20Deployed(token, to);
    }
}
