// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {IEulerSwapPeriphery} from "euler-swap/src/interfaces/IEulerSwapPeriphery.sol";
import {IEulerSwap} from "euler-swap/src/interfaces/IEulerSwap.sol";
import {Eulaunch} from "../Eulaunch.sol";
import {LiquidityManager, Resources} from "../LiquidityManager.sol";
import {TokenSuiteFactory} from "../TokenSuiteFactory.sol";
import {ICreateX} from "../vendor/ICreateX.sol";

/// @title EulaunchLens
/// @notice A data entry aggregator for Eulaunch.
contract EulaunchLens {
    ICreateX public constant CREATEX = ICreateX(0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
    address public immutable eulaunch;
    address public immutable eulerSwapPeriphery;

    error PoolNotFound();
    error InvalidTokens();

    constructor(address _eulaunch, address _eulerSwapPeriphery) {
        eulaunch = _eulaunch;
        eulerSwapPeriphery = _eulerSwapPeriphery;
    }

    function getTotalResources() external view returns (uint256 total) {
        total = Eulaunch(eulaunch).getTotalResources();
    }

    function getAllBaseTokensByQuoteToken(address quoteToken, uint256 limit, uint256 offset)
        external
        view
        returns (address[] memory baseTokens, uint256 total)
    {
        (baseTokens, total) = Eulaunch(eulaunch).getAllBaseTokensByQuoteToken(quoteToken, limit, offset);
    }

    function getAllResourcesByQuoteToken(address quoteToken, uint256 limit, uint256 offset)
        external
        view
        returns (Resources[] memory resources, uint256 total)
    {
        (resources, total) = Eulaunch(eulaunch).getAllResourcesByQuoteToken(quoteToken, limit, offset);
    }

    /// @notice Gets the pool by tokens.
    /// @dev If the pool is not found, it will return address(0).
    /// @param tokenA The address of the first token.
    /// @param tokenB The address of the second token.
    /// @return pool The address of the pool.
    function getPool(address tokenA, address tokenB) public view returns (address pool) {
        pool = Eulaunch(eulaunch).getPoolByBaseToken(tokenA);
        if (pool == address(0)) {
            pool = Eulaunch(eulaunch).getPoolByBaseToken(tokenB);
        }
    }

    /// @notice Gets the amount of output tokens for a given amount of input tokens.
    /// @param tokenIn The address of the input token.
    /// @param tokenOut The address of the output token.
    /// @param amountIn The amount of input tokens.
    /// @return amountOut The amount of output tokens.
    function quoteExactInput(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 amountOut)
    {
        address eulerSwap = getPool(tokenIn, tokenOut);
        require(eulerSwap != address(0), PoolNotFound());
        amountOut = IEulerSwapPeriphery(eulerSwapPeriphery).quoteExactInput(eulerSwap, tokenIn, tokenOut, amountIn);
    }

    /// @notice Gets the amount of input tokens for a given amount of output tokens.
    /// @param tokenIn The address of the input token.
    /// @param tokenOut The address of the output token.
    /// @param amountOut The amount of output tokens.
    /// @return amountIn The amount of input tokens.
    function quoteExactOutput(address tokenIn, address tokenOut, uint256 amountOut)
        external
        view
        returns (uint256 amountIn)
    {
        address eulerSwap = getPool(tokenIn, tokenOut);
        require(eulerSwap != address(0), PoolNotFound());
        amountIn = IEulerSwapPeriphery(eulerSwapPeriphery).quoteExactOutput(eulerSwap, tokenIn, tokenOut, amountOut);
    }

    /// @notice Upper-bounds on the amounts of each token that this pool can currently support swaps for.
    /// @param tokenIn The address of the input token.
    /// @param tokenOut The address of the output token.
    /// @return maxAmountIn Maximum amount of input token that can be deposited.
    /// @return maxAmountOut Maximum amount of output token that can be withdrawn.
    function getLimits(address tokenIn, address tokenOut)
        external
        view
        returns (uint256 maxAmountIn, uint256 maxAmountOut)
    {
        address eulerSwap = getPool(tokenIn, tokenOut);
        require(eulerSwap != address(0), PoolNotFound());
        (maxAmountIn, maxAmountOut) = IEulerSwap(eulerSwap).getLimits(tokenIn, tokenOut);
    }

    // aderyn-ignore-next-line(internal-function-used-once)
    function switcheroo(address tokenA, address tokenB) internal view returns (bool) {
        require(tokenA != tokenB, InvalidTokens());
        require(tokenA != address(0) && tokenB != address(0), InvalidTokens());
        address eulerSwap = getPool(tokenA, tokenB);
        require(eulerSwap != address(0), PoolNotFound());
        (address asset0,) = IEulerSwap(eulerSwap).getAssets();
        return asset0 == tokenB;
    }

    /// @notice Gets the reserves of the pool.
    /// @param tokenA The address of the first token.
    /// @param tokenB The address of the second token.
    /// @return reserveIn The reserve of the first token.
    /// @return reserveOut The reserve of the second token.
    function getReserves(address tokenA, address tokenB)
        external
        view
        returns (uint256 reserveIn, uint256 reserveOut)
    {
        address eulerSwap = getPool(tokenA, tokenB);
        require(eulerSwap != address(0), PoolNotFound());
        (uint112 reserve0, uint112 reserve1,) = IEulerSwap(eulerSwap).getReserves();
        if (switcheroo(tokenA, tokenB)) {
            return (reserve1, reserve0);
        } else {
            return (reserve0, reserve1);
        }
    }

    function previewEscrowVault() external view returns (address vault) {
        vault = TokenSuiteFactory(Eulaunch(eulaunch).tokenSuiteFactory()).previewEscrowVault();
    }

    /// @notice Preview the address of contract that would be deployed with the given salt.
    ///         Crosschain deployment protection is applied.
    /// @param salt The salt for the CREATE3 deployment via CREATEX.
    /// @return deployment The address of the contract that would be deployed.
    function previewCreate3(bytes32 salt) external view returns (address deployment) {
        bytes32 guardedSalt = _efficientHash({a: bytes32(block.chainid), b: salt});
        deployment = CREATEX.computeCreate3Address(guardedSalt);
    }

    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            hash := keccak256(0x00, 0x40)
        }
    }
}
