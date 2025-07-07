// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {IEVault} from "evk/EVault/IEVault.sol";
import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {EulerSwapFactory} from "euler-swap/src/EulerSwapFactory.sol";
import {IEulerSwap} from "euler-swap/src/interfaces/IEulerSwap.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {EulaunchOmni} from "./EulaunchOmni.sol";

/// @notice Resources linked to the EulerSwap instance.
struct Resources {
    address eulerSwap;
    address liquidityManager;
    address token0;
    address vault0;
    address token1;
    address vault1;
}

/// @title Liquidity Manager Omni
/// @notice A liquidity manager for EulerSwap. It owns the EulerSwap instance, and is fully owned by an owner.
// aderyn-ignore-next-line(centralization-risk, contract-locks-ether)
contract LiquidityManagerOmni is Ownable {
    address public immutable eulaunch;
    address public immutable evc;
    address public immutable eulerSwapFactory;
    address public immutable token0;
    address public immutable token1;
    address public immutable vault0;
    address public immutable vault1;

    bool public initialized_;
    bool public closed_;
    address public eulerSwap_;

    error NotEulaunch();
    error AlreadyClosed();

    event Initialized(address indexed token0, address indexed token1);
    event EulerSwapDeployed(address indexed eulerSwap);
    event Closed(address indexed token0, address indexed token1, address indexed eulerSwap);
    event Withdrawn(
        address indexed token0, address indexed token1, address indexed to, uint256 amount0, uint256 amount1
    );

    /// @notice Constructor for the liquidity manager.
    /// @param _evc The address of the Ethereum Vault Connector.
    /// @param _eulerSwapFactory The address of the EulerSwap factory.
    /// @param _eulaunch The address of the Eulaunch factory.
    /// @param _poolParams The parameters for the EulerSwap instance.
    /// @param _initialState The initial state of the EulerSwap instance.
    /// @param _salt The salt for the EulerSwap instance (aka `hookSalt`).
    /// @param _owner The privileged owner of this liquidity pool.
    constructor(
        address _evc,
        address _eulerSwapFactory,
        address _eulaunch,
        IEulerSwap.Params memory _poolParams,
        IEulerSwap.InitialState memory _initialState,
        bytes32 _salt,
        address _owner
    ) {
        // aderyn-ignore-next-line(reentrancy-state-change)
        require(EulaunchOmni(_eulaunch).isEulaunch(), NotEulaunch());
        evc = _evc;
        eulerSwapFactory = _eulerSwapFactory;
        eulaunch = _eulaunch;
        vault0 = _poolParams.vault0;
        vault1 = _poolParams.vault1;
        // aderyn-ignore-next-line(reentrancy-state-change)
        token0 = IEVault(vault0).asset();
        token1 = IEVault(vault1).asset();

        _initialize(_poolParams, _initialState, _salt);
        _initializeOwner(_owner);
    }

    // aderyn-ignore-next-line(modifier-used-only-once)
    modifier onlyCloseOnce() {
        require(!closed_, AlreadyClosed());
        closed_ = true;
        _;
        emit Closed(token0, token1, eulerSwap_);
    }

    /// @notice Initializes the liquidity manager by deploying the EulerSwap instance.
    /// @param poolParams The parameters for the EulerSwap instance.
    /// @param initialState The initial state of the EulerSwap instance.
    /// @param salt The salt for the EulerSwap instance (aka `hookSalt`).
    function _initialize(IEulerSwap.Params memory poolParams, IEulerSwap.InitialState memory initialState, bytes32 salt)
        internal
    {
        SafeTransferLib.safeTransferFrom(token0, eulaunch, address(this), initialState.currReserve0);
        SafeTransferLib.safeApprove(token0, vault0, initialState.currReserve0);
        // aderyn-ignore-next-line(reentrancy-state-change, unchecked-return)
        IEVault(vault0).deposit(initialState.currReserve0, address(this));

        SafeTransferLib.safeTransferFrom(token1, eulaunch, address(this), initialState.currReserve1);
        SafeTransferLib.safeApprove(token1, vault1, initialState.currReserve1);
        // aderyn-ignore-next-line(reentrancy-state-change, unchecked-return)
        IEVault(vault1).deposit(initialState.currReserve1, address(this));

        // aderyn-ignore-next-line(reentrancy-state-change)
        address eulerSwap = EulerSwapFactory(eulerSwapFactory).computePoolAddress(poolParams, salt);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);
        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeCall(IEVC.setAccountOperator, (address(this), eulerSwap, true))
        });
        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: address(this),
            targetContract: eulerSwapFactory,
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.deployPool, (poolParams, initialState, salt))
        });

        // aderyn-ignore-next-line(reentrancy-state-change)
        IEVC(evc).batch(items);
        eulerSwap_ = eulerSwap;

        emit EulerSwapDeployed(eulerSwap);
    }

    /// @notice Closes the liquidity manager by uninstalling the EulerSwap instance and withdrawing all the base/quote tokens to the given address.
    /// @dev This function is only callable by the owner.
    /// @param to The address to withdraw the base/quote tokens to.
    /// @return amount0 The amount of base tokens withdrawn.
    /// @return amount1 The amount of quote tokens withdrawn.
    // aderyn-ignore-next-line(centralization-risk)
    function close(address to) external onlyOwner onlyCloseOnce returns (uint256 amount0, uint256 amount1) {
        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);
        items[0] = IEVC.BatchItem({
            targetContract: address(evc),
            onBehalfOfAccount: address(0),
            value: 0,
            data: abi.encodeCall(IEVC.setAccountOperator, (address(this), eulerSwap_, false))
        });
        items[1] = IEVC.BatchItem({
            targetContract: address(eulerSwapFactory),
            onBehalfOfAccount: address(this),
            value: 0,
            data: abi.encodeCall(EulerSwapFactory.uninstallPool, ())
        });
        IEVC(evc).batch(items);

        uint256 maxWithdrawBase = IEVault(vault0).maxWithdraw(address(this));
        uint256 maxWithdrawQuote = IEVault(vault1).maxWithdraw(address(this));

        amount0 = IEVault(vault0).withdraw(maxWithdrawBase, to, address(this));
        amount1 = IEVault(vault1).withdraw(maxWithdrawQuote, to, address(this));
        emit Withdrawn(token0, token1, to, amount0, amount1);
    }

    /// @notice Returns the resources linked to the EulerSwap instance.
    /// @return resources The resources linked to the EulerSwap instance.
    function getResources() external view returns (Resources memory resources) {
        resources = Resources({
            eulerSwap: eulerSwap_,
            liquidityManager: address(this),
            token0: token0,
            vault0: vault0,
            token1: token1,
            vault1: vault1
        });
    }

    /// @notice Executes an arbitrary transaction through the liquidity manager as a smart wallet.
    /// @dev This function is only callable by the owner.
    /// @param target The contract to call.
    /// @param data The data to call the contract with.
    /// @param value The value to send with the transaction.
    // aderyn-ignore-next-line(centralization-risk)
    function exec(address target, bytes calldata data, uint256 value) external payable onlyOwner {
        (bool success, bytes memory reason) = target.call{value: value}(data);
        require(success, string(reason));
    }
}
