// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {ERC20} from "solady/tokens/ERC20.sol";
import {IEulerSwapPeriphery} from "euler-swap/src/interfaces/IEulerSwapPeriphery.sol";
import {IEulerSwap} from "euler-swap/src/interfaces/IEulerSwap.sol";
import {EulaunchOmni} from "../EulaunchOmni.sol";
import {LiquidityManagerOmni, Resources} from "../LiquidityManagerOmni.sol";
import {ICreateX} from "../../vendor/ICreateX.sol";

struct PoolState {
    // Resources
    address eulerSwap;
    address liquidityManager;
    address token0;
    address vault0;
    address token1;
    address vault1;
    // Curve parameters
    uint112 equilibriumReserve0;
    uint112 equilibriumReserve1;
    uint256 priceX;
    uint256 priceY;
    uint256 concentrationX;
    uint256 concentrationY;
    // Fees
    uint256 fee;
    uint256 protocolFee;
    address protocolFeeRecipient;
    // Reserves
    uint112 reserve0;
    uint112 reserve1;
}

/// @title EulaunchOmniLens
/// @notice A data entry aggregator for EulaunchOmni.
contract EulaunchOmniLens {
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
        total = EulaunchOmni(eulaunch).getTotalResources();
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
