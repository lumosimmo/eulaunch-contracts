// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {TokenSuiteFactory, ERC20Params} from "./TokenSuiteFactory.sol";
import {LiquidityManager, CurveParams, ProtocolFeeParams, VaultParams, Resources} from "./LiquidityManager.sol";
import {ICreateX} from "../vendor/ICreateX.sol";

/// @title Eulaunch Factory
/// @notice A token factory and liquidity bootstrapping platform for EulerSwap.
contract Eulaunch {
    ICreateX public constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
    address public immutable evc;
    address public immutable eulerSwapFactory;
    address public immutable tokenSuiteFactory;

    Resources[] internal allResources_;
    address[] internal allPools_;
    address[] internal allBaseTokens_;
    mapping(address quoteToken => address[] baseTokens) internal quoteTokenToBaseTokensMap_;
    mapping(address baseToken => address quoteToken) internal baseTokenToQuoteTokenMap_;

    // These maps are 1-indexed
    mapping(address pool => uint256 index) internal poolIndexMap_;
    mapping(address baseToken => uint256 index) internal baseTokenIndexMap_;
    mapping(address liquidityManager => uint256 index) internal liquidityManagerIndexMap_;

    error InvalidQuoteVault();
    error ResourcesNotFound();

    event Launched(address indexed baseToken, address indexed quoteToken, address indexed eulerSwap, uint256 index);

    constructor(address _evc, address _eulerSwapFactory, address _tokenSuiteFactory) {
        evc = _evc;
        eulerSwapFactory = _eulerSwapFactory;
        tokenSuiteFactory = _tokenSuiteFactory;
    }

    /// @notice Creates a new token, an EulerSwap instance, and a LiquidityManager owning the instance.
    /// @param tokenParams The details for the base token to deploy with.
    /// @param tokenSalt The salt to deploy the base token via CreateX.
    /// @param quoteVault The address of the quote vault.
    /// @param curveParams The AMM curve parameters.
    /// @param fee The swap fee.
    /// @param protocolFeeParams The EulerSwap protocol fee parameters.
    /// @param lmSalt The salt to deploy the LiquidityManager via CreateX.
    /// @param hookSalt The salt to deploy the EulerSwap hook.
    function launch(
        ERC20Params memory tokenParams,
        bytes32 tokenSalt,
        address quoteVault,
        CurveParams memory curveParams,
        uint256 fee,
        ProtocolFeeParams memory protocolFeeParams,
        bytes32 lmSalt,
        bytes32 hookSalt
    ) external returns (Resources memory resources) {
        address quoteToken = IEVault(quoteVault).asset();
        require(quoteToken != address(0), InvalidQuoteVault());

        VaultParams memory vaultParams;
        {
            address baseToken = TokenSuiteFactory(tokenSuiteFactory).deployERC20(tokenParams, address(this), tokenSalt);
            address baseVault = TokenSuiteFactory(tokenSuiteFactory).deployEscrowVault(baseToken);

            vaultParams = VaultParams({
                baseToken: baseToken,
                quoteToken: quoteToken,
                baseVault: baseVault,
                quoteVault: quoteVault
            });
        }

        address liquidityManager;
        {
            bytes memory args = abi.encode(evc, eulerSwapFactory, address(this), vaultParams, msg.sender);
            // aderyn-ignore-next-line(abi-encode-packed-hash-collision)
            bytes memory initCode = abi.encodePacked(type(LiquidityManager).creationCode, args);

            liquidityManager = CREATEX.deployCreate3(lmSalt, initCode);
        }

        SafeTransferLib.safeApprove(vaultParams.baseToken, liquidityManager, tokenParams.totalSupply);

        resources = LiquidityManager(liquidityManager).initialize(
            curveParams, uint112(tokenParams.totalSupply), fee, protocolFeeParams, hookSalt
        );
        _addResources(resources);
        emit Launched(resources.baseToken, resources.quoteToken, resources.eulerSwap, allResources_.length);
    }

    /// @dev For sanity check assertion purposes.
    function isEulaunch() external pure returns (bool) {
        return true;
    }

    function _addResources(Resources memory resources) internal {
        allResources_.push(resources);
        allPools_.push(resources.eulerSwap);
        allBaseTokens_.push(resources.baseToken);
        quoteTokenToBaseTokensMap_[resources.quoteToken].push(resources.baseToken);
        baseTokenToQuoteTokenMap_[resources.baseToken] = resources.quoteToken;

        poolIndexMap_[resources.eulerSwap] = allResources_.length;
        baseTokenIndexMap_[resources.baseToken] = allResources_.length;
        liquidityManagerIndexMap_[resources.liquidityManager] = allResources_.length;
    }

    function previewLiquidityManager(bytes32 salt) external view returns (address lm) {
        bytes32 guardedSalt = _efficientHash({a: bytes32(block.chainid), b: salt});
        lm = CREATEX.computeCreate3Address(guardedSalt);
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

    /// @notice Gets the pool by the base token.
    /// @param baseToken The address of the base token.
    /// @return pool The pool linked to the base token.
    function getPoolByBaseToken(address baseToken) external view returns (address pool) {
        uint256 index = baseTokenIndexMap_[baseToken];
        require(index != 0, ResourcesNotFound());
        return allPools_[index - 1];
    }

    /// @notice Gets the resources by the liquidity manager.
    /// @param liquidityManager The address of the liquidity manager.
    /// @return resources The resources linked to the liquidity manager.
    function getResourcesByLiquidityManager(address liquidityManager) external view returns (Resources memory) {
        uint256 index = liquidityManagerIndexMap_[liquidityManager];
        require(index != 0, ResourcesNotFound());
        return allResources_[index - 1];
    }

    /// @notice Gets the resources by the index.
    /// @param index The index of the resources.
    /// @return resources The resources linked to the index.
    function getResourcesByIndex(uint256 index) external view returns (Resources memory) {
        require(index != 0, ResourcesNotFound());
        return allResources_[index - 1];
    }

    /// @notice Gets the base token by the index.
    /// @param index The index of the base token.
    /// @return baseToken The base token linked to the index.
    function getBaseTokenByIndex(uint256 index) external view returns (address baseToken) {
        require(index != 0, ResourcesNotFound());
        return allBaseTokens_[index - 1];
    }

    /// @notice Gets the quote token by the base token.
    /// @param baseToken The address of the base token.
    /// @return quoteToken The quote token linked to the base token.
    function getQuoteTokenByBaseToken(address baseToken) external view returns (address quoteToken) {
        quoteToken = baseTokenToQuoteTokenMap_[baseToken];
        require(quoteToken != address(0), ResourcesNotFound());
    }

    /// @notice Gets all the resources with pagination.
    /// @param limit The number of resources to return.
    /// @param offset The offset for pagination.
    /// @return resources An array of resources.
    /// @return total The total number of resources.
    function getAllResources(uint256 limit, uint256 offset)
        external
        view
        returns (Resources[] memory resources, uint256 total)
    {
        uint256 length = allResources_.length;
        total = length;

        if (offset >= length) {
            return (new Resources[](0), total);
        }

        uint256 remaining = length - offset;
        if (limit > remaining) {
            limit = remaining;
        }

        resources = new Resources[](limit);
        for (uint256 i = 0; i < limit; i++) {
            resources[i] = allResources_[offset + i];
        }
    }

    /// @notice Gets all the base tokens by the quote token with pagination.
    /// @param quoteToken The address of the quote token.
    /// @param limit The number of base tokens to return.
    /// @param offset The offset for pagination.
    /// @return baseTokens An array of base tokens.
    /// @return total The total number of base tokens.
    function getAllBaseTokensByQuoteToken(address quoteToken, uint256 limit, uint256 offset)
        external
        view
        returns (address[] memory baseTokens, uint256 total)
    {
        address[] storage baseTokens_ = quoteTokenToBaseTokensMap_[quoteToken];
        uint256 length = baseTokens_.length;
        total = length;

        if (offset >= length) {
            return (new address[](0), total);
        }

        uint256 remaining = length - offset;
        if (limit > remaining) {
            limit = remaining;
        }

        baseTokens = new address[](limit);
        for (uint256 i = 0; i < limit; i++) {
            baseTokens[i] = baseTokens_[offset + i];
        }

        return (baseTokens, total);
    }

    /// @notice Gets all the resources by the quote token with pagination.
    /// @param quoteToken The address of the quote token.
    /// @param limit The number of resources to return.
    /// @param offset The offset for pagination.
    /// @return resources An array of resources.
    /// @return total The total number of resources.
    function getAllResourcesByQuoteToken(address quoteToken, uint256 limit, uint256 offset)
        external
        view
        returns (Resources[] memory resources, uint256 total)
    {
        address[] storage baseTokens_ = quoteTokenToBaseTokensMap_[quoteToken];
        uint256 length = baseTokens_.length;
        total = length;

        if (offset >= length) {
            return (new Resources[](0), total);
        }

        uint256 remaining = length - offset;
        if (limit > remaining) {
            limit = remaining;
        }

        resources = new Resources[](limit);
        for (uint256 i = 0; i < limit; i++) {
            address baseToken = baseTokens_[offset + i];
            uint256 index = baseTokenIndexMap_[baseToken];
            resources[i] = allResources_[index - 1];
        }

        return (resources, total);
    }

    /// @notice Gets the total number of resources or pools launched via this contract.
    /// @return total The total number of resources.
    function getTotalResources() external view returns (uint256 total) {
        total = allResources_.length;
    }

    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            hash := keccak256(0x00, 0x40)
        }
    }
}
