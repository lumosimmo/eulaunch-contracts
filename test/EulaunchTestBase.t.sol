// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {EulerSwapTestBase} from "euler-swap/test/EulerSwapTestBase.t.sol";
import {CreateX} from "./vendor/CreateX.sol";
import {EscrowedCollateralPerspective} from "evk-periphery/src/Perspectives/deployed/EscrowedCollateralPerspective.sol";

contract EulaunchTestBase is EulerSwapTestBase {
    EscrowedCollateralPerspective internal perspective;

    function setUp() public virtual override {
        // Set the chain to Unichain to pin CreateX computations
        vm.chainId(130);

        super.setUp();

        deployCodeTo("CreateX.sol", 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed);
        perspective = new EscrowedCollateralPerspective(address(factory));
    }
}
