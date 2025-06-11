// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {LibRLP} from "solady/utils/LibRLP.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IEVC} from "evc/interfaces/IEthereumVaultConnector.sol";
import {TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {QuoteLib} from "euler-swap/src/libraries/QuoteLib.sol";
import {HookMiner, Hooks} from "euler-swap/test/utils/HookMiner.sol";
import {IEulerSwap} from "euler-swap/src/interfaces/IEulerSwap.sol";
import {EulaunchTestBase} from "./EulaunchTestBase.t.sol";
import {Eulaunch} from "../src/Eulaunch.sol";
import {LiquidityManager} from "../src/LiquidityManager.sol";
import {TokenSuiteFactory} from "../src/TokenSuiteFactory.sol";
import {QuoteVaultRegistry} from "../src/QuoteVaultRegistry.sol";
import {BasicAsset} from "../src/tokens/BasicAsset.sol";
import {Resources, CurveParams, VaultParams, ProtocolFeeParams} from "../src/LiquidityManager.sol";
import {ERC20Params} from "../src/TokenSuiteFactory.sol";

contract EulaunchTest is EulaunchTestBase {
    Eulaunch internal eulaunch;
    TokenSuiteFactory internal tokenSuiteFactory;
    QuoteVaultRegistry internal quoteVaultRegistry;

    function setUp() public override {
        super.setUp();

        vm.startPrank(deployer);
        tokenSuiteFactory = new TokenSuiteFactory(address(factory), address(perspective));
        quoteVaultRegistry = new QuoteVaultRegistry(address(eulerSwapFactory));
        eulaunch = new Eulaunch(
            address(evc), address(eulerSwapFactory), address(tokenSuiteFactory), address(quoteVaultRegistry)
        );

        // We will be using TST3 as the quote token
        quoteVaultRegistry.setQuoteVault(address(assetTST3), address(eTST3));
        vm.stopPrank();
    }

    function _launchSingleSided(uint256 totalSupply) internal returns (Resources memory resources) {
        address _baseToken = tokenSuiteFactory.previewERC20(salt1);
        assertNotEq(_baseToken, address(0), "Base token should be definable");
        address _baseVault = tokenSuiteFactory.previewEscrowVault();
        assertNotEq(_baseVault, address(0), "Base vault should be definable");
        address _lm = eulaunch.previewLiquidityManager();
        assertNotEq(_lm, address(0), "LiquidityManager should be definable");

        ERC20Params memory tokenParams = ERC20Params({name: "TokenForSale", symbol: "TFS", totalSupply: totalSupply});
        CurveParams memory curveParams = CurveParams({
            equilibriumReserveBase: uint112(tokenParams.totalSupply),
            equilibriumReserveQuote: 0,
            priceBase: 1e18,
            priceQuote: 1e18,
            concentrationBase: 0.85e18,
            concentrationQuote: 0.4e18
        });
        uint256 fee = 0;
        ProtocolFeeParams memory protocolFeeParams =
            ProtocolFeeParams({protocolFee: 0, protocolFeeRecipient: address(0)});

        bool switcheroo = _baseToken < address(assetTST3);

        IEulerSwap.Params memory poolParams = IEulerSwap.Params({
            vault0: switcheroo ? _baseVault : address(eTST3),
            vault1: switcheroo ? address(eTST3) : _baseVault,
            eulerAccount: _lm,
            equilibriumReserve0: switcheroo ? uint112(tokenParams.totalSupply) : 0,
            equilibriumReserve1: switcheroo ? 0 : uint112(tokenParams.totalSupply),
            priceX: 1e18,
            priceY: 1e18,
            concentrationX: switcheroo ? 0.85e18 : 0.4e18,
            concentrationY: switcheroo ? 0.4e18 : 0.85e18,
            fee: fee,
            protocolFee: 0,
            protocolFeeRecipient: address(0)
        });
        (address _eulerSwap, bytes32 hookSalt) = mineSalt(poolParams);

        vm.startPrank(user1);
        resources =
            eulaunch.launch(tokenParams, salt1, address(assetTST3), curveParams, fee, protocolFeeParams, hookSalt);
        vm.stopPrank();

        assertTrue(resources.baseToken == token1, "Base token mismatch");
        assertTrue(resources.quoteToken == address(assetTST3), "Quote token mismatch");
        assertTrue(resources.baseVault != address(0), "Base vault mismatch");
        assertTrue(resources.quoteVault == address(eTST3), "Quote vault mismatch");
        assertTrue(resources.liquidityManager != address(0), "Liquidity manager mismatch");
        assertTrue(resources.eulerSwap == _eulerSwap, "EulerSwap pool mismatch");
    }

    function test_Launch() public {
        _launchSingleSided(60 ether);
    }

    function test_Accounting() public {
        Resources memory resources = _launchSingleSided(1000 ether);

        assertEq(
            BasicAsset(resources.baseToken).balanceOf(resources.liquidityManager),
            0,
            "LiquidityManager should own 0 base tokens"
        );
        assertEq(BasicAsset(resources.baseToken).balanceOf(user1), 0, "User should own 0 base tokens");
        assertEq(IEVault(resources.baseVault).totalAssets(), 1000 ether, "Base vault should have 1000 assets");

        assertEq(IEVault(resources.baseVault).balanceOf(user1), 0, "User should own 0 base vault shares");
        assertEq(
            IEVault(resources.baseVault).balanceOf(resources.liquidityManager),
            1000 ether,
            "LiquidityManager should own 1000 base vault shares"
        );
        assertEq(
            IEVault(resources.quoteVault).balanceOf(resources.liquidityManager),
            0,
            "LiquidityManager should own 0 quote vault shares"
        );
        assertEq(IEVault(resources.quoteVault).balanceOf(user1), 0, "User should own 0 quote vault shares");
    }

    /// @notice These curve tests are adapted from `euler-swap/test/OneSidedCurve.t.sol`.
    ///         The base/quote order is switched compared to the original tests.
    function test_Curve() public {
        Resources memory resources = _launchSingleSided(60 ether);

        // Nothing available
        {
            uint256 amountOut = periphery.quoteExactInput(
                address(resources.eulerSwap), address(resources.baseToken), address(resources.quoteToken), 1e18
            );
            assertEq(amountOut, 0, "Nothing available: amountOut should be 0");
        }

        // Swap in available direction
        {
            uint256 amountIn = 1e18;
            uint256 amountOut = periphery.quoteExactInput(
                address(resources.eulerSwap), address(resources.quoteToken), address(resources.baseToken), amountIn
            );
            assertApproxEqAbs(amountOut, 0.9974e18, 0.0001e18, "Swapping 1e18 quote -> base, delta too high");

            TestERC20(resources.quoteToken).mint(address(this), amountIn);
            TestERC20(resources.quoteToken).transfer(address(resources.eulerSwap), amountIn);
            IEulerSwap(resources.eulerSwap).swap(amountOut, 0, address(this), "");

            assertEq(
                BasicAsset(resources.baseToken).balanceOf(address(this)),
                amountOut,
                "Swapping 1e18 quote -> base, predicted amountOut mismatches actual output"
            );
        }

        // Quote back exact amount in
        {
            uint256 amountIn = BasicAsset(resources.baseToken).balanceOf(address(this));
            uint256 amountOut = periphery.quoteExactInput(
                address(resources.eulerSwap), address(resources.baseToken), address(resources.quoteToken), amountIn
            );
            assertEq(amountOut, 1e18, "Quote back exact amount in, amountOut mismatch");
        }

        // Swap back with some extra, no more available
        {
            uint256 amountIn = BasicAsset(resources.baseToken).balanceOf(address(this)) + 1e18;
            uint256 amountOut = periphery.quoteExactInput(
                address(resources.eulerSwap), address(resources.baseToken), address(resources.quoteToken), amountIn
            );
            assertEq(amountOut, 1e18, "Quote back some extra amount in, amountOut should be be the full 1e18 reserve");
        }

        // Quote exact out amount in, and do swap
        {
            uint256 amountIn;

            vm.expectRevert(QuoteLib.SwapLimitExceeded.selector);
            amountIn = periphery.quoteExactOutput(
                address(resources.eulerSwap), address(resources.baseToken), address(resources.quoteToken), 1e18
            );

            uint256 amountOut = 1e18 - 1;
            amountIn = periphery.quoteExactOutput(
                address(resources.eulerSwap), address(resources.baseToken), address(resources.quoteToken), amountOut
            );

            assertEq(amountIn, BasicAsset(resources.baseToken).balanceOf(address(this)));

            BasicAsset(resources.baseToken).transfer(address(resources.eulerSwap), amountIn);
            IEulerSwap(resources.eulerSwap).swap(0, amountOut, address(this), "");
        }

        // Nothing available again (except dust left-over from previous swap)
        {
            uint256 amountOut = periphery.quoteExactInput(
                address(resources.eulerSwap), address(resources.baseToken), address(resources.quoteToken), 1e18
            );
            assertEq(amountOut, 1, "Nothing should be available again, amountOut should be dust");
        }
    }

    // TODO: These are now LiquidityManager tests, will refactor tomorrow

    function test_Close() public {
        Resources memory resources = _launchSingleSided(60 ether);

        vm.startPrank(user1);
        (uint256 baseAmount, uint256 quoteAmount) = LiquidityManager(resources.liquidityManager).close(user1);
        vm.stopPrank();

        assertEq(baseAmount, 60 ether, "Base amount mismatch");
        assertEq(quoteAmount, 0, "Quote amount mismatch");

        assertEq(BasicAsset(resources.baseToken).balanceOf(user1), 60 ether, "User should own 60 base tokens");
        assertEq(BasicAsset(resources.quoteToken).balanceOf(user1), 0, "User should own 0 quote tokens");
    }

    function test_Close_AfterSwaps() public {
        Resources memory resources = _launchSingleSided(60 ether);

        {
            uint256 amountIn = 1e18;
            uint256 amountOut = periphery.quoteExactInput(
                address(resources.eulerSwap), address(resources.quoteToken), address(resources.baseToken), amountIn
            );
            TestERC20(resources.quoteToken).mint(address(this), amountIn);
            TestERC20(resources.quoteToken).transfer(address(resources.eulerSwap), amountIn);
            IEulerSwap(resources.eulerSwap).swap(amountOut, 0, address(this), "");
        }

        vm.startPrank(user1);
        (uint256 baseAmount, uint256 quoteAmount) = LiquidityManager(resources.liquidityManager).close(user1);
        vm.stopPrank();

        assertApproxEqAbs(baseAmount, 60 ether - 0.9974e18, 0.0001e18, "Base amount delta too high");
        assertEq(quoteAmount, 1 ether, "Quote amount mismatch");

        assertApproxEqAbs(
            BasicAsset(resources.baseToken).balanceOf(user1),
            60 ether - 0.9974e18,
            0.0001e18,
            "User should own around 59.0026 base tokens after closing"
        );
        assertEq(
            BasicAsset(resources.quoteToken).balanceOf(user1), 1 ether, "User should own 1 quote token after closing"
        );
    }

    function test_Close_WhenNotOwner_ShouldRevert() public {
        Resources memory resources = _launchSingleSided(60 ether);

        vm.startPrank(user2);
        vm.expectRevert(abi.encodeWithSelector(Ownable.Unauthorized.selector));
        LiquidityManager(resources.liquidityManager).close(user2);
        vm.stopPrank();
    }
}
