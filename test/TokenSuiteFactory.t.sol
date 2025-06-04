// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {EulaunchTestBase} from "./EulaunchTestBase.t.sol";
import {TokenSuiteFactory} from "src/TokenSuiteFactory.sol";
import {BasicAsset} from "src/tokens/BasicAsset.sol";

contract TokenSuiteFactoryTest is EulaunchTestBase {
    uint256 internal constant INITIAL_SUPPLY = 1_000_000_000 ether;

    TokenSuiteFactory internal tokenSuiteFactory;
    address internal deployer;
    address internal user1;
    address internal user2;

    // We use predefined salt and address for testing purposes
    bytes32 internal salt1 = 0x00000000000000000000000000000000000000000184568cce2890f4036e59b6;
    address internal token1 = 0x2718ef58B01429627CC3751F1ac5e7b82578783f;
    bytes32 internal salt2 = 0x0000000000000000000000000000000000000000015ca316f75cb2f1030a8960;
    address internal token2 = 0x27181d370eEACbAd5Abd3AE0432685f559111325;

    function setUp() public override {
        super.setUp();

        deployer = address(this);
        vm.label(deployer, "Deployer");
        user1 = vm.addr(2);
        vm.label(user1, "User1");
        user2 = vm.addr(3);
        vm.label(user2, "User2");

        vm.startPrank(deployer);
        tokenSuiteFactory = new TokenSuiteFactory(address(eulerSwapFactory), address(factory), address(perspective));
        vm.stopPrank();
    }

    function test_DeployERC20() public {
        vm.startPrank(user1);
        address token = tokenSuiteFactory.deployERC20("TestAsset", "TA", user1, INITIAL_SUPPLY, salt1);
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
        tokenSuiteFactory.deployERC20(longName, "TA", user1, INITIAL_SUPPLY, salt1);
        vm.stopPrank();
    }

    function test_DeployERC20_WhenSymbolTooLong_ShouldRevert() public {
        vm.startPrank(user1);
        string memory longSymbol = "THIS SYMBOL IS WAY TOO LONG FOR ANY TOKEN";
        vm.expectRevert(TokenSuiteFactory.SymbolTooLong.selector);
        tokenSuiteFactory.deployERC20("TestAsset", longSymbol, user1, INITIAL_SUPPLY, salt1);
        vm.stopPrank();
    }
}
