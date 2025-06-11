// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {EulaunchTestBase} from "./EulaunchTestBase.t.sol";
import {TokenSuiteFactory, ERC20Params} from "src/TokenSuiteFactory.sol";
import {BasicAsset} from "src/tokens/BasicAsset.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {Errors} from "evk/EVault/shared/Errors.sol";
import {SafeERC20Lib} from "evk/EVault/shared/lib/SafeERC20Lib.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

contract TokenSuiteFactoryTest is EulaunchTestBase {
    uint256 internal constant INITIAL_SUPPLY = 1_000_000_000 ether;

    TokenSuiteFactory internal tokenSuiteFactory;

    // We use predefined salt and address for testing purposes
    bytes32 internal salt1 = 0x00000000000000000000000000000000000000000184568cce2890f4036e59b6;
    address internal token1 = 0x2718ef58B01429627CC3751F1ac5e7b82578783f;
    bytes32 internal salt2 = 0x0000000000000000000000000000000000000000015ca316f75cb2f1030a8960;
    address internal token2 = 0x27181d370eEACbAd5Abd3AE0432685f559111325;

    function setUp() public override {
        super.setUp();

        vm.startPrank(deployer);
        tokenSuiteFactory = new TokenSuiteFactory(address(factory), address(perspective));
        vm.stopPrank();
    }

    function test_DeployERC20() public {
        vm.startPrank(user1);
        ERC20Params memory params = ERC20Params({name: "TestAsset", symbol: "TA", totalSupply: INITIAL_SUPPLY});
        address token = tokenSuiteFactory.deployERC20(params, user1, salt1);
        vm.stopPrank();
        assertEq(token, token1);
        assertEq(BasicAsset(token).balanceOf(user1), INITIAL_SUPPLY);
        assertEq(BasicAsset(token).totalSupply(), INITIAL_SUPPLY);
        assertEq(BasicAsset(token).name(), "TestAsset");
        assertEq(BasicAsset(token).symbol(), "TA");
        assertEq(BasicAsset(token).decimals(), 18);
    }

    function test_DeployERC20_WhenNameTooLong_ShouldRevert() public {
        vm.startPrank(user1);
        string memory longName = "ThisNameIsDefinitelyWayTooLongForAnyToken";
        vm.expectRevert(TokenSuiteFactory.NameTooLong.selector);
        ERC20Params memory params = ERC20Params({name: longName, symbol: "TA", totalSupply: INITIAL_SUPPLY});
        tokenSuiteFactory.deployERC20(params, user1, salt1);
        vm.stopPrank();
    }

    function test_DeployERC20_WhenSymbolTooLong_ShouldRevert() public {
        vm.startPrank(user1);
        string memory longSymbol = "THIS SYMBOL IS WAY TOO LONG FOR ANY TOKEN";
        vm.expectRevert(TokenSuiteFactory.SymbolTooLong.selector);
        ERC20Params memory params = ERC20Params({name: "TestAsset", symbol: longSymbol, totalSupply: INITIAL_SUPPLY});
        tokenSuiteFactory.deployERC20(params, user1, salt1);
        vm.stopPrank();
    }

    function test_DeployEscrowVault() public {
        vm.startPrank(user1);
        ERC20Params memory params = ERC20Params({name: "TestAsset", symbol: "TA", totalSupply: INITIAL_SUPPLY});
        address token = tokenSuiteFactory.deployERC20(params, user1, salt1);
        address vault = tokenSuiteFactory.deployEscrowVault(token);
        vm.stopPrank();
        assertTrue(vault != address(0), "Vault address should not be zero");
        assertEq(IEVault(vault).asset(), token, "Vault asset mismatch");
        assertTrue(perspective.isVerified(vault), "Vault not verified by perspective");
        assertEq(IEVault(vault).governorAdmin(), address(0), "Vault governor not renounced");

        (address hookTarget, uint32 hookedOps) = IEVault(vault).hookConfig();
        assertEq(hookTarget, address(0), "Hook target not address(0)");
        assertEq(hookedOps, 0, "Hooked ops not 0");
    }

    function test_DeployEscrowVault_ShouldAllowDeposit() public {
        vm.startPrank(user1);
        ERC20Params memory params = ERC20Params({name: "TestAsset", symbol: "TA", totalSupply: INITIAL_SUPPLY});
        address token = tokenSuiteFactory.deployERC20(params, user1, salt1);
        address vault = tokenSuiteFactory.deployEscrowVault(token);

        uint256 depositAmount = 100 ether;
        BasicAsset(token).approve(vault, depositAmount);
        uint256 sharesReceived = IEVault(vault).deposit(depositAmount, user1);

        vm.stopPrank();

        assertEq(
            BasicAsset(token).balanceOf(user1),
            INITIAL_SUPPLY - depositAmount,
            "User token balance incorrect after deposit"
        );
        assertEq(IEVault(vault).totalAssets(), depositAmount, "Vault total assets incorrect after deposit");
        assertEq(IEVault(vault).balanceOf(user1), sharesReceived, "User share balance incorrect after deposit");
        // Shares should equal assets deposited for escrow vaults
        assertEq(
            IEVault(vault).convertToAssets(sharesReceived),
            depositAmount,
            "Shares received do not equate to assets deposited"
        );
        assertEq(BasicAsset(token).balanceOf(vault), depositAmount, "Vault token balance incorrect after deposit");
    }

    function test_DeployEscrowVault_ShouldAllowWithdraw() public {
        vm.startPrank(user1);
        ERC20Params memory params = ERC20Params({name: "TestAsset", symbol: "TA", totalSupply: INITIAL_SUPPLY});
        address token = tokenSuiteFactory.deployERC20(params, user1, salt1);
        address vault = tokenSuiteFactory.deployEscrowVault(token);

        uint256 depositAmount = 200 ether;
        BasicAsset(token).approve(vault, depositAmount);
        IEVault(vault).deposit(depositAmount, user1);
        uint256 userSharesBeforeWithdraw = IEVault(vault).balanceOf(user1);
        uint256 userTokensBeforeWithdraw = BasicAsset(token).balanceOf(user1);

        uint256 withdrawTokenAmount = 100 ether;
        uint256 sharesBurnt = IEVault(vault).withdraw(withdrawTokenAmount, user1, user1);

        vm.stopPrank();

        assertEq(
            BasicAsset(token).balanceOf(user1),
            userTokensBeforeWithdraw + withdrawTokenAmount,
            "User token balance incorrect after withdraw"
        );
        assertEq(
            IEVault(vault).totalAssets(),
            depositAmount - withdrawTokenAmount,
            "Vault total assets incorrect after withdraw"
        );
        assertEq(
            IEVault(vault).balanceOf(user1),
            userSharesBeforeWithdraw - sharesBurnt,
            "User share balance incorrect after withdraw"
        );
        assertEq(
            IEVault(vault).convertToAssets(sharesBurnt),
            withdrawTokenAmount,
            "Shares burnt do not equate to assets withdrawn"
        );
    }

    function test_DeployEscrowVault_WhenDepositMoreThanBalance_ShouldRevert() public {
        vm.startPrank(user1);
        ERC20Params memory params = ERC20Params({name: "TestAsset", symbol: "TA", totalSupply: INITIAL_SUPPLY});
        address token = tokenSuiteFactory.deployERC20(params, user1, salt1);
        address vault = tokenSuiteFactory.deployEscrowVault(token);

        uint256 badDepositAmount = INITIAL_SUPPLY + 1 ether;
        BasicAsset(token).approve(vault, badDepositAmount);

        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Lib.E_TransferFromFailed.selector,
                abi.encodeWithSelector(IAllowanceTransfer.AllowanceExpired.selector, 0),
                abi.encodeWithSelector(ERC20.InsufficientBalance.selector)
            )
        );
        IEVault(vault).deposit(badDepositAmount, user1);
        vm.stopPrank();
    }

    function test_DeployEscrowVault_WhenDepositMoreThanAllowance_ShouldRevert() public {
        vm.startPrank(user1);
        ERC20Params memory params = ERC20Params({name: "TestAsset", symbol: "TA", totalSupply: INITIAL_SUPPLY});
        address token = tokenSuiteFactory.deployERC20(params, user1, salt1);
        address vault = tokenSuiteFactory.deployEscrowVault(token);

        uint256 depositAmount = 100 ether;
        uint256 allowance = 50 ether;
        BasicAsset(token).approve(vault, allowance);

        vm.expectRevert(
            abi.encodeWithSelector(
                SafeERC20Lib.E_TransferFromFailed.selector,
                abi.encodeWithSelector(IAllowanceTransfer.AllowanceExpired.selector, 0),
                abi.encodeWithSelector(ERC20.InsufficientAllowance.selector)
            )
        );
        IEVault(vault).deposit(depositAmount, user1);
        vm.stopPrank();
    }

    function test_DeployEscrowVault_WhenWithdrawMoreThanDeposited_ShouldRevert() public {
        vm.startPrank(user1);
        ERC20Params memory params = ERC20Params({name: "TestAsset", symbol: "TA", totalSupply: INITIAL_SUPPLY});
        address token = tokenSuiteFactory.deployERC20(params, user1, salt1);
        address vault = tokenSuiteFactory.deployEscrowVault(token);

        uint256 depositAmount = 100 ether;
        BasicAsset(token).approve(vault, depositAmount);
        IEVault(vault).deposit(depositAmount, user1);

        uint256 withdrawAmount = depositAmount + 1 ether;
        vm.expectRevert(Errors.E_InsufficientCash.selector);
        IEVault(vault).withdraw(withdrawAmount, user1, user1);
        vm.stopPrank();
    }

    function test_DeployEscrowVault_WhenWithdrawWithNoDeposit_ShouldRevert() public {
        vm.startPrank(user1);
        ERC20Params memory params = ERC20Params({name: "TestAsset", symbol: "TA", totalSupply: INITIAL_SUPPLY});
        address token = tokenSuiteFactory.deployERC20(params, user1, salt1);
        address vault = tokenSuiteFactory.deployEscrowVault(token);

        uint256 withdrawAmount = 100 ether;
        vm.expectRevert(Errors.E_InsufficientCash.selector);
        IEVault(vault).withdraw(withdrawAmount, user1, user1);
        vm.stopPrank();
    }

    function test_DeployEscrowVault_WhenWithdrawWithWrongAccount_ShouldRevert() public {
        vm.startPrank(user1);
        ERC20Params memory params = ERC20Params({name: "TestAsset", symbol: "TA", totalSupply: INITIAL_SUPPLY});
        address token = tokenSuiteFactory.deployERC20(params, user1, salt1);
        address vault = tokenSuiteFactory.deployEscrowVault(token);

        uint256 depositAmount = 100 ether;
        BasicAsset(token).approve(vault, depositAmount);
        IEVault(vault).deposit(depositAmount, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        uint256 withdrawAmount = 10 ether;

        // User2 should not be permitted to touch user1's shares
        vm.expectRevert(Errors.E_InsufficientAllowance.selector);
        IEVault(vault).withdraw(withdrawAmount, user2, user1);

        // User2 does not have any shares, so they should not be able to withdraw
        vm.expectRevert(Errors.E_InsufficientBalance.selector);
        IEVault(vault).withdraw(withdrawAmount, user2, user2);
        vm.stopPrank();
    }
}
