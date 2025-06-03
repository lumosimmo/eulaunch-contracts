// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {EulerSwapTestBase} from "euler-swap/test/EulerSwapTestBase.t.sol";

contract EulaunchTestBase is EulerSwapTestBase {
    function setUp() public override virtual {
        super.setUp();
    }
}
