// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {ERC20} from "solady/tokens/ERC20.sol";
import {IEulerSwapPeriphery} from "euler-swap/src/interfaces/IEulerSwapPeriphery.sol";
import {IEulerSwap} from "euler-swap/src/interfaces/IEulerSwap.sol";
import {Eulaunch} from "../Eulaunch.sol";
import {LiquidityManager, Resources} from "../LiquidityManager.sol";
import {TokenSuiteFactory} from "../TokenSuiteFactory.sol";
import {ICreateX} from "../vendor/ICreateX.sol";

struct PoolState {
    // Resources
    address eulerSwap;
    address liquidityManager;
    address baseToken;
    address baseVault;
    address quoteToken;
    address quoteVault;
    // Curve parameters
    uint112 equilibriumReserveBase;
    uint112 equilibriumReserveQuote;
    uint256 priceBase;
    uint256 priceQuote;
    uint256 concentrationBase;
    uint256 concentrationQuote;
    // Reserves
    uint256 reserveBase;
    uint256 reserveQuote;
}

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

    /// @notice Gets the state of the pool.
    /// @param pool The address of the pool.
    /// @return state The state of the pool.
    function getPoolState(address pool) public view returns (PoolState memory state) {
        Resources memory resources = Eulaunch(eulaunch).getResourcesByPool(pool);
        state.eulerSwap = resources.eulerSwap;
        state.liquidityManager = resources.liquidityManager;
        state.baseToken = resources.baseToken;
        state.baseVault = resources.baseVault;
        state.quoteToken = resources.quoteToken;
        state.quoteVault = resources.quoteVault;

        (state.reserveBase, state.reserveQuote) = getReserves(state.baseToken, state.quoteToken);
        IEulerSwap.Params memory params = getParams(state.baseToken, state.quoteToken);

        if (switcheroo(state.baseToken, state.quoteToken)) {
            state.equilibriumReserveBase = params.equilibriumReserve1;
            state.equilibriumReserveQuote = params.equilibriumReserve0;
            state.priceBase = params.priceY;
            state.priceQuote = params.priceX;
            state.concentrationBase = params.concentrationY;
            state.concentrationQuote = params.concentrationX;
        } else {
            state.equilibriumReserveBase = params.equilibriumReserve0;
            state.equilibriumReserveQuote = params.equilibriumReserve1;
            state.priceBase = params.priceX;
            state.priceQuote = params.priceY;
            state.concentrationBase = params.concentrationX;
            state.concentrationQuote = params.concentrationY;
        }
    }

    /// @notice Gets the state of the pool by base token.
    /// @param token The address of the base token.
    /// @return state The state of the pool.
    function getPoolStateByBaseToken(address token) external view returns (PoolState memory state) {
        address pool = Eulaunch(eulaunch).getPoolByBaseToken(token);
        require(pool != address(0), PoolNotFound());
        state = getPoolState(pool);
    }

    /// @notice Calculates the avg price of buying `tokenOut` with `amountIn` of `tokenIn`.
    /// @param tokenIn The address of the input token.
    /// @param tokenOut The address of the output token.
    /// @param amountIn The amount of input tokens.
    /// @return price The price of buying `tokenOut` with `amountIn` of `tokenIn` in WAD, decimals of tokens are normalized to 18.
    function getPrice(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256 price) {
        uint256 amountOut = quoteExactInput(tokenIn, tokenOut, amountIn);
        // Either side of the tokenIn/Out can be 18 decimals or 6 decimals, so we need to normalize the decimals
        uint256 decimalsIn = ERC20(tokenIn).decimals();
        uint256 decimalsOut = ERC20(tokenOut).decimals();
        uint256 normalizedAmountIn = amountIn * 10 ** (18 - decimalsIn);
        uint256 normalizedAmountOut = amountOut * 10 ** (18 - decimalsOut);
        price = normalizedAmountOut * 10 ** 18 / normalizedAmountIn;
    }

    /// @notice Gets the amount of output tokens for a given amount of input tokens.
    /// @param tokenIn The address of the input token.
    /// @param tokenOut The address of the output token.
    /// @param amountIn The amount of input tokens.
    /// @return amountOut The amount of output tokens.
    function quoteExactInput(address tokenIn, address tokenOut, uint256 amountIn)
        public
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
    /// @return reserveA The reserve of the first token.
    /// @return reserveB The reserve of the second token.
    function getReserves(address tokenA, address tokenB) public view returns (uint256 reserveA, uint256 reserveB) {
        address eulerSwap = getPool(tokenA, tokenB);
        require(eulerSwap != address(0), PoolNotFound());
        (uint112 reserve0, uint112 reserve1,) = IEulerSwap(eulerSwap).getReserves();
        if (switcheroo(tokenA, tokenB)) {
            return (reserve1, reserve0);
        } else {
            return (reserve0, reserve1);
        }
    }

    /// @notice Gets the parameters of the pool.
    /// @param tokenA The address of the first token.
    /// @param tokenB The address of the second token.
    /// @return params The parameters of the pool.
    function getParams(address tokenA, address tokenB) public view returns (IEulerSwap.Params memory params) {
        address eulerSwap = getPool(tokenA, tokenB);
        require(eulerSwap != address(0), PoolNotFound());
        params = IEulerSwap(eulerSwap).getParams();
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
