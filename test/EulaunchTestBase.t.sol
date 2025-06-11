// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {EulerSwapTestBase} from "euler-swap/test/EulerSwapTestBase.t.sol";
import {CreateX} from "./vendor/CreateX.sol";
import {EscrowedCollateralPerspective} from "./vendor/evk-periphery/EscrowedCollateralPerspective.sol";

contract EulaunchTestBase is EulerSwapTestBase {
    EscrowedCollateralPerspective internal perspective;

    address internal deployer;
    address internal user1;
    address internal user2;
    address internal user3;

    function setUp() public virtual override {
        // Set the chain to Unichain to pin CreateX computations
        vm.chainId(130);

        deployer = vm.addr(1);
        vm.label(deployer, "Deployer");
        user1 = vm.addr(2);
        vm.label(user1, "User1");
        user2 = vm.addr(3);
        vm.label(user2, "User2");
        user3 = vm.addr(4);
        vm.label(user3, "User3");

        super.setUp();

        deployCodeTo("CreateX.sol", 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
        perspective = new EscrowedCollateralPerspective(address(factory));
    }
}
