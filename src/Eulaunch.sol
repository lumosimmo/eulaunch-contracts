// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {TokenSuiteFactory, ERC20Params} from "./TokenSuiteFactory.sol";
import {QuoteVaultRegistry} from "./QuoteVaultRegistry.sol";
import {LiquidityManager, CurveParams, ProtocolFeeParams, VaultParams, Resources} from "./LiquidityManager.sol";

/// @title Eulaunch Factory
/// @notice A token factory and liquidity bootstrapping platform for EulerSwap.
contract Eulaunch {
    address public immutable evc;
    address public immutable eulerSwapFactory;
    address public immutable tokenSuiteFactory;
    address public immutable quoteVaultRegistry;

    Resources[] internal allResources_;
    // These maps are 1-indexed
    mapping(address pool => uint256 index) internal poolIndexMap_;
    mapping(address baseToken => uint256 index) internal baseTokenIndexMap_;

    error QuoteVaultNotFound();
    error ResourcesNotFound();

    event Launched(address indexed baseToken, address indexed quoteToken, address indexed eulerSwap, uint256 index);

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
        Resources memory resources =
            liquidityManager.initialize(curveParams, uint112(tokenParams.totalSupply), fee, protocolFeeParams, hookSalt);
        _addResources(resources);
        emit Launched(resources.baseToken, resources.quoteToken, resources.eulerSwap, allResources_.length);
    }

    /// @dev For sanity check assertion purposes.
    function isEulaunch() external pure returns (bool) {
        return true;
    }

    function _addResources(Resources memory resources) internal {
        allResources_.push(resources);
        poolIndexMap_[resources.eulerSwap] = allResources_.length;
        baseTokenIndexMap_[resources.baseToken] = allResources_.length;
    }

    /// @notice Gets the resources by the EulerSwap instance.
    /// @param pool The address of the EulerSwap instance.
    /// @return resources The resources linked to the EulerSwap instance.
    function getResourcesByPool(address pool) external view returns (Resources memory) {
        uint256 index = poolIndexMap_[pool];
        require(index != 0, ResourcesNotFound());
        return allResources_[index - 1];
    }

    /// @notice Gets the resources by the base token.
    /// @param baseToken The address of the base token.
    /// @return resources The resources linked to the base token.
    function getResourcesByBaseToken(address baseToken) external view returns (Resources memory) {
        uint256 index = baseTokenIndexMap_[baseToken];
        require(index != 0, ResourcesNotFound());
        return allResources_[index - 1];
    }

    /// @notice Gets the resources by the index.
    /// @param index The index of the resources.
    /// @return resources The resources linked to the index.
    function getResources(uint256 index) external view returns (Resources memory) {
        require(index != 0, ResourcesNotFound());
        return allResources_[index - 1];
    }
}
