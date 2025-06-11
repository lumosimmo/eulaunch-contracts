// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {TokenSuiteFactory, ERC20Params} from "./TokenSuiteFactory.sol";
import {QuoteVaultRegistry} from "./QuoteVaultRegistry.sol";
import {LiquidityManager, CurveParams, ProtocolFeeParams, VaultParams} from "./LiquidityManager.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

/// @title Eulaunch Factory
/// @notice A token factory and liquidity bootstrapping platform for EulerSwap.
contract Eulaunch {
    address public immutable evc;
    address public immutable eulerSwapFactory;
    address public immutable tokenSuiteFactory;
    address public immutable quoteVaultRegistry;

    error QuoteVaultNotFound();

    constructor(address _evc, address _eulerSwapFactory, address _tokenSuiteFactory, address _quoteVaultRegistry) {
        evc = _evc;
        eulerSwapFactory = _eulerSwapFactory;
        tokenSuiteFactory = _tokenSuiteFactory;
        quoteVaultRegistry = _quoteVaultRegistry;
    }

    /// @notice Creates a new token, an EulerSwap instance, and a LiquidityManager owning the instance.
    /// @param tokenParams The details for the base token to deploy with.
    /// @param tokenSalt The salt to deploy the base token via CreateX.
    /// @param quoteToken The address of the quote token.
    /// @param curveParams The AMM curve parameters.
    /// @param fee The swap fee.
    /// @param protocolFeeParams The EulerSwap protocol fee parameters.
    /// @param hookSalt The salt to deploy the EulerSwap hook.
    function launch(
        ERC20Params memory tokenParams,
        bytes32 tokenSalt,
        address quoteToken,
        CurveParams memory curveParams,
        uint256 fee,
        ProtocolFeeParams memory protocolFeeParams,
        bytes32 hookSalt
    ) external {
        address quoteVault = QuoteVaultRegistry(quoteVaultRegistry).getQuoteVault(quoteToken);
        require(quoteVault != address(0), QuoteVaultNotFound());

        address baseToken = TokenSuiteFactory(tokenSuiteFactory).deployERC20(tokenParams, address(this), tokenSalt);
        address baseVault = TokenSuiteFactory(tokenSuiteFactory).deployEscrowVault(baseToken);

        LiquidityManager liquidityManager = new LiquidityManager(
            evc,
            eulerSwapFactory,
            VaultParams({baseToken: baseToken, quoteToken: quoteToken, baseVault: baseVault, quoteVault: quoteVault}),
            msg.sender
        );

        SafeTransferLib.safeApprove(baseToken, address(liquidityManager), tokenParams.totalSupply);

        // aderyn-ignore-next-line(unchecked-return)
        liquidityManager.initialize(curveParams, uint112(tokenParams.totalSupply), fee, protocolFeeParams, hookSalt);
    }

    /// @dev For sanity check assertion purposes.
    function isEulaunch() external pure returns (bool) {
        return true;
    }
}
