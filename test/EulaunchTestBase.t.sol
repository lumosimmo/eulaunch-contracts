// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {FactoryTest} from "euler-swap/test/FactoryTest.t.sol";
import {CreateX} from "./vendor/CreateX.sol";
import {EscrowedCollateralPerspective} from "./vendor/evk-periphery/EscrowedCollateralPerspective.sol";

contract EulaunchTestBase is FactoryTest {
    EscrowedCollateralPerspective internal perspective;

    address internal deployer;
    address internal user1;
    address internal user2;
    address internal user3;

    // We use predefined salt and address for testing purposes
    bytes32 internal immutable salt1 = 0x00000000000000000000000000000000000000000184568cce2890f4036e59b6;
    address internal immutable token1 = 0x2718ef58B01429627CC3751F1ac5e7b82578783f;
    bytes32 internal immutable salt2 = 0x0000000000000000000000000000000000000000015ca316f75cb2f1030a8960;
    address internal immutable token2 = 0x27181d370eEACbAd5Abd3AE0432685f559111325;

    bytes32 internal immutable lmSalt1 = 0x000000000000000000000000000000000000000001000000004c03bd8abbcc48;
    address internal immutable lm1 = 0xEEeeb9772F8383829ebabd39B5cA1ED53735c817;

    function setUp() public virtual override {
        // Set the chain to Unichain to pin CreateX computations
        vm.chainId(130);

        deployer = makeAddr("deployer");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        super.setUp();

        deployCodeTo("CreateX.sol", 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
        perspective = new EscrowedCollateralPerspective(address(factory));
    }
}
