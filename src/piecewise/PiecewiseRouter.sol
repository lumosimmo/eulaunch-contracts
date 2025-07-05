// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {IEulerSwapPeriphery} from "euler-swap/src/interfaces/IEulerSwapPeriphery.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

/// @title Piecewise Router
/// @notice A router for the Piecewise EulerSwap aggregator.
contract PiecewiseRouter {
    address public immutable eulerSwapPeriphery;

    struct SwapAllocation {
        address pool;
        uint256 amountIn;
    }

    error InvalidRoute();
    error AmountOutLessThanMin();
    error DeadlineExpired();

    event SwapExactInFlatRoutes(
        address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, address indexed receiver
    );

    constructor(address _eulerSwapPeriphery) {
        eulerSwapPeriphery = _eulerSwapPeriphery;
    }

    /// @notice Executes a split-aggregate swap with the given flat routes.
    /// @dev We do not sanity check the routes beyond the fact that they are non-empty to save gas.
    ///      The swap is valid as long as all asserts pass and the transfers do not revert.
    /// @param routes The routes to swap through.
    /// @param tokenIn The token to swap from.
    /// @param tokenOut The token to swap to.
    /// @param amountIn The amount of `tokenIn` to swap.
    /// @param receiver The address to receive the output tokens.
    function swapExactInFlatRoutes(
        SwapAllocation[] memory routes,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address receiver,
        uint256 amountOutMin,
        uint256 deadline
    ) external {
        require(deadline == 0 || deadline >= block.timestamp, DeadlineExpired());
        require(routes.length > 0, InvalidRoute());

        SafeTransferLib.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
        SafeTransferLib.safeApprove(tokenIn, eulerSwapPeriphery, amountIn);

        for (uint256 i = 0; i < routes.length; i++) {
            swapExactInSingle(routes[i].pool, tokenIn, tokenOut, routes[i].amountIn);
        }
        uint256 amountOut = ERC20(tokenOut).balanceOf(address(this));

        require(amountOut >= amountOutMin, AmountOutLessThanMin());
        SafeTransferLib.safeTransfer(tokenOut, receiver, amountOut);
    }

    /// @notice Handles a single swap step, settles tokens to the router.
    // aderyn-ignore-next-line(internal-function-used-once)
    function swapExactInSingle(address pool, address tokenIn, address tokenOut, uint256 amountIn) internal {
        IEulerSwapPeriphery(eulerSwapPeriphery).swapExactIn(
            pool, tokenIn, tokenOut, amountIn, address(this), 0, block.timestamp
        );
    }
}
