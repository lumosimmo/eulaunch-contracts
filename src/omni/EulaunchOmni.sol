// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IEulerSwap} from "euler-swap/src/interfaces/IEulerSwap.sol";
import {LiquidityManagerOmni, Resources} from "./LiquidityManagerOmni.sol";
import {ICreateX} from "../vendor/ICreateX.sol";

/// @title Eulaunch Omni Factory
/// @notice A LP bootstrapping platform for EulerSwap.
contract EulaunchOmni {
    ICreateX public constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
    address public immutable evc;
    address public immutable eulerSwapFactory;

    Resources[] internal allResources_;
    address[] internal allPools_;
    address[] internal allBaseTokens_;
    mapping(address token1 => address[] token0) internal token1ToToken0Map_;
    mapping(address token0 => address[] token1) internal token0ToToken1Map_;

    // These maps are 1-indexed
    mapping(address pool => uint256 index) internal poolIndexMap_;
    mapping(address liquidityManager => uint256 index) internal liquidityManagerIndexMap_;
    mapping(bytes32 pair => uint256 index) internal pairIndexMap_;

    error InvalidQuoteVault();
    error InvalidBaseVault();
    error InvalidTokenOrder();
    error InvalidLiquidityManager();
    error InvalidLmSalt();
    error ResourcesNotFound();

    event Launched(address indexed baseToken, address indexed quoteToken, address indexed eulerSwap, uint256 index);

    constructor(address _evc, address _eulerSwapFactory) {
        evc = _evc;
        eulerSwapFactory = _eulerSwapFactory;
    }

    /// @notice Creates a new token, an EulerSwap instance, and a LiquidityManager owning the instance.
    /// @param poolParams The parameters for the EulerSwap instance.
    /// @param initialState The initial state of the EulerSwap instance.
    /// @param lmSalt The salt to deploy the LiquidityManager via CreateX.
    /// @param hookSalt The salt to deploy the EulerSwap hook.
    function launch(
        IEulerSwap.Params memory poolParams,
        IEulerSwap.InitialState memory initialState,
        bytes32 lmSalt,
        bytes32 hookSalt
    ) external returns (Resources memory resources) {
        address token0 = IEVault(poolParams.vault0).asset();
        require(token0 != address(0), InvalidBaseVault());
        address token1 = IEVault(poolParams.vault1).asset();
        require(token1 != address(0), InvalidQuoteVault());
        require(token0 < token1, InvalidTokenOrder());

        address lm = previewLiquidityManager(lmSalt);
        require(lm == poolParams.eulerAccount, InvalidLmSalt());
        require(lm != address(0), InvalidLiquidityManager());

        SafeTransferLib.safeTransferFrom(token0, msg.sender, address(this), initialState.currReserve0);
        SafeTransferLib.safeTransferFrom(token1, msg.sender, address(this), initialState.currReserve1);

        SafeTransferLib.safeApprove(token0, lm, initialState.currReserve0);
        SafeTransferLib.safeApprove(token1, lm, initialState.currReserve1);

        bytes memory args =
            abi.encode(evc, eulerSwapFactory, address(this), poolParams, initialState, hookSalt, msg.sender);
        // aderyn-ignore-next-line(abi-encode-packed-hash-collision)
        bytes memory initCode = abi.encodePacked(type(LiquidityManagerOmni).creationCode, args);

        address deployedLm = CREATEX.deployCreate3(lmSalt, initCode);
        require(deployedLm == lm, InvalidLiquidityManager());

        resources = LiquidityManagerOmni(lm).getResources();

        _addResources(resources);
        emit Launched(resources.token0, resources.token1, resources.eulerSwap, allResources_.length);
    }

    /// @dev For sanity check assertion purposes.
    function isEulaunch() external pure returns (bool) {
        return true;
    }

    function _addResources(Resources memory resources) internal {
        allResources_.push(resources);
        allPools_.push(resources.eulerSwap);
        allBaseTokens_.push(resources.token0);
        token1ToToken0Map_[resources.token1].push(resources.token0);
        token0ToToken1Map_[resources.token0].push(resources.token1);

        poolIndexMap_[resources.eulerSwap] = allResources_.length;
        liquidityManagerIndexMap_[resources.liquidityManager] = allResources_.length;
        pairIndexMap_[keccak256(abi.encode(resources.token0, resources.token1))] = allResources_.length;
    }

    function previewLiquidityManager(bytes32 salt) public view returns (address lm) {
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

    /// @notice Gets the resources by the pair.
    /// @param token0 The address of the first token.
    /// @param token1 The address of the second token.
    /// @return resources The resources linked to the pair.
    function getResourcesByPair(address token0, address token1) external view returns (Resources memory) {
        require(token0 < token1, InvalidTokenOrder());
        uint256 index = pairIndexMap_[keccak256(abi.encode(token0, token1))];
        require(index != 0, ResourcesNotFound());
        return allResources_[index - 1];
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
