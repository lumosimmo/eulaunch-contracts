// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {IEVault} from "evk/EVault/IEVault.sol";
import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {EulerSwapFactory} from "euler-swap/src/EulerSwapFactory.sol";
import {IEulerSwap} from "euler-swap/src/interfaces/IEulerSwap.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {Eulaunch} from "./Eulaunch.sol";

/// @notice Addresses for the assets and vaults in the curve.
/// @dev The base/quote tokens here are not sorted. The base token is always the new token to bootstrap liquidity for.
struct VaultParams {
    address baseToken;
    address baseVault;
    address quoteToken;
    address quoteVault;
}

/// @notice Parameters for the EulerSwap curve.
/// @dev The base/quote tokens here are not sorted.
struct CurveParams {
    uint112 equilibriumReserveBase;
    uint112 equilibriumReserveQuote;
    uint256 priceBase;
    uint256 priceQuote;
    uint256 concentrationBase;
    uint256 concentrationQuote;
}

/// @notice Parameters for the EulerSwap protocol fee.
/// @dev Needed in `EulerSwapFactory.deployPool()`.
struct ProtocolFeeParams {
    uint256 protocolFee;
    address protocolFeeRecipient;
}

/// @title Liquidity Manager
/// @notice A liquidity manager for EulerSwap. It owns the EulerSwap instance, and is fully owned by an owner.
// aderyn-ignore-next-line(centralization-risk)
contract LiquidityManager is Ownable {
    address public immutable eulaunch;
    address public immutable evc;
    address public immutable eulerSwapFactory;
    address public immutable baseToken;
    address public immutable quoteToken;
    address public immutable baseVault;
    address public immutable quoteVault;

    bool public initialized_;
    bool public closed_;
    address public eulerSwap_;

    error NotEulaunch();
    error AlreadyClosed();

    event Initialized(address indexed baseToken, address indexed quoteToken);
    event EulerSwapDeployed(address indexed eulerSwap);
    event Closed(address indexed baseToken, address indexed quoteToken, address indexed eulerSwap);
    event Withdrawn(
        address indexed baseToken,
        address indexed quoteToken,
        address indexed to,
        uint256 baseAmount,
        uint256 quoteAmount
    );

    /// @notice Constructor for the liquidity manager.
    /// @param _evc The address of the Ethereum Vault Connector.
    /// @param _eulerSwapFactory The address of the EulerSwap factory.
    /// @param _vaultParams The parameters for the vaults. The base/quote tokens here are not sorted.
    /// @param _owner The privileged owner of this liquidity pool.
    constructor(address _evc, address _eulerSwapFactory, VaultParams memory _vaultParams, address _owner) {
        // aderyn-ignore-next-line(reentrancy-state-change)
        require(Eulaunch(msg.sender).isEulaunch(), NotEulaunch());
        eulaunch = msg.sender;
        evc = _evc;
        eulerSwapFactory = _eulerSwapFactory;
        baseToken = _vaultParams.baseToken;
        quoteToken = _vaultParams.quoteToken;
        baseVault = _vaultParams.baseVault;
        quoteVault = _vaultParams.quoteVault;
        _initializeOwner(_owner);
    }

    // aderyn-ignore-next-line(modifier-used-only-once)
    modifier onlyEulaunch() {
        require(msg.sender == eulaunch, NotEulaunch());
        _;
    }

    // aderyn-ignore-next-line(modifier-used-only-once)
    modifier onlyInitializeOnce() {
        require(!initialized_, AlreadyInitialized());
        initialized_ = true;
        _;
        emit Initialized(baseToken, quoteToken);
    }

    modifier onlyCloseOnce() {
        require(!closed_, AlreadyClosed());
        closed_ = true;
        _;
        emit Closed(baseToken, quoteToken, eulerSwap_);
    }

    /// @notice Initializes the liquidity manager by funding the base vault and deploying the EulerSwap instance.
    /// @dev The EulerSwap curve will be a single-sided curve with 0 initial reserve on the quote token side.
    ///      This contract needs to be pre-funded with the base token before calling this function.
    ///      The base/quote tokens here are not sorted.
    /// @param curveParams The parameters for the curve.
    /// @param initialReserveBase The initial reserve of the base token.
    /// @param fee The swap fee.
    /// @param protocolFeeParams The parameters for the protocol fee.
    /// @param salt The salt for the EulerSwap instance. Not to be confused with the salt in `TokenSuiteFactory.deployERC20()`.
    /// @return baseShares The number of shares of the base token in the base vault. This should equal to `initialReserveBase`.
    /// @return eulerSwap The address of the EulerSwap instance deployed.

    function initialize(
        CurveParams memory curveParams,
        uint112 initialReserveBase,
        uint256 fee,
        ProtocolFeeParams memory protocolFeeParams,
        bytes32 salt
    ) external onlyEulaunch onlyInitializeOnce returns (uint256 baseShares, address eulerSwap) {
        baseShares = _handleBase(baseToken, baseVault, initialReserveBase);

        bool switcheroo = baseToken > quoteToken;

        IEulerSwap.Params memory poolParams = IEulerSwap.Params({
            vault0: switcheroo ? quoteVault : baseVault,
            vault1: switcheroo ? baseVault : quoteVault,
            eulerAccount: address(this),
            equilibriumReserve0: switcheroo ? curveParams.equilibriumReserveQuote : curveParams.equilibriumReserveBase,
            equilibriumReserve1: switcheroo ? curveParams.equilibriumReserveBase : curveParams.equilibriumReserveQuote,
            priceX: switcheroo ? curveParams.priceQuote : curveParams.priceBase,
            priceY: switcheroo ? curveParams.priceBase : curveParams.priceQuote,
            concentrationX: switcheroo ? curveParams.concentrationQuote : curveParams.concentrationBase,
            concentrationY: switcheroo ? curveParams.concentrationBase : curveParams.concentrationQuote,
            fee: fee,
            protocolFee: protocolFeeParams.protocolFee,
            protocolFeeRecipient: protocolFeeParams.protocolFeeRecipient
        });
        // aderyn-ignore-next-line(reentrancy-state-change)
        eulerSwap = EulerSwapFactory(eulerSwapFactory).computePoolAddress(poolParams, salt);

        IEulerSwap.InitialState memory initialState = IEulerSwap.InitialState({
            currReserve0: switcheroo ? 0 : initialReserveBase,
            currReserve1: switcheroo ? initialReserveBase : 0
        });

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

    function _handleBase(address token, address vault, uint256 amount) internal returns (uint256 shares) {
        SafeTransferLib.safeApprove(token, vault, amount);
        shares = IEVault(vault).deposit(amount, address(this));
    }

    /// @notice Closes the liquidity manager by uninstalling the EulerSwap instance and withdrawing all the base/quote tokens to the given address.
    /// @dev This function is only callable by the owner.
    /// @param to The address to withdraw the base/quote tokens to.
    /// @return baseAmount The amount of base tokens withdrawn.
    /// @return quoteAmount The amount of quote tokens withdrawn.
    // aderyn-ignore-next-line(centralization-risk)
    function close(address to) external onlyOwner onlyCloseOnce returns (uint256 baseAmount, uint256 quoteAmount) {
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

        uint256 maxWithdrawBase = IEVault(baseVault).maxWithdraw(address(this));
        uint256 maxWithdrawQuote = IEVault(quoteVault).maxWithdraw(address(this));

        baseAmount = IEVault(baseVault).withdraw(maxWithdrawBase, to, address(this));
        quoteAmount = IEVault(quoteVault).withdraw(maxWithdrawQuote, to, address(this));
        emit Withdrawn(baseToken, quoteToken, to, baseAmount, quoteAmount);
    }

    /// @notice Executes any transaction on behalf of this LiquidityManager.
    /// @dev The LiquidityManager is fully owned by the owner so this function is useful for future-proofing.
    /// @param target The address of the contract to call.
    /// @param data The data to call the contract with.
    /// @param value The value to send with the call.
    // aderyn-ignore-next-line(centralization-risk)
    function execTransaction(address target, bytes calldata data, uint256 value) external onlyOwner {
        (bool success, bytes memory reason) = target.call{value: value}(data);
        require(success, string(reason));
    }
}
