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

    function setUp() public override {
        super.setUp();

        deployer = address(this);
        vm.label(deployer, "Deployer");
        user1 = vm.addr(2);
        vm.label(user1, "User1");
        user2 = vm.addr(3);
        vm.label(user2, "User2");

        vm.startPrank(deployer);
        tokenSuiteFactory = new TokenSuiteFactory(address(eulerSwapFactory));
        vm.stopPrank();
    }

    function test_DeployERC20() public {
        vm.startPrank(user1);
        // We use predefined salt and address for testing purposes
        bytes32 salt = bytes32(uint256(0x00000000000000000000000000000000000000000184568cce2890f4036e59b6));
        address token = tokenSuiteFactory.deployERC20("TestAsset", "TA", user1, INITIAL_SUPPLY, salt);
        vm.stopPrank();
        assertEq(token, 0x2718ef58B01429627CC3751F1ac5e7b82578783f);
        assertEq(BasicAsset(token).balanceOf(user1), INITIAL_SUPPLY);
        assertEq(BasicAsset(token).totalSupply(), INITIAL_SUPPLY);
        assertEq(BasicAsset(token).name(), "TestAsset");
        assertEq(BasicAsset(token).symbol(), "TA");
        assertEq(BasicAsset(token).decimals(), 18);
    }
}
