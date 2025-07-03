// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import "forge-std/Script.sol";
import {EulaunchLens} from "src/v1/periphery/EulaunchLens.sol";

contract DeployEulaunchLens is Script {
    address public constant eulerSwapPeriphery = 0xdAAF468d84DD8945521Ea40297ce6c5EEfc7003a;
    address public constant eulaunch = 0x55BC055328Fe23C571976Ddb8a0EEe3FF66E8D4f;

    function run() public {
        vm.createSelectFork("unichain");
        uint256 deployerKey = vm.envUint("WALLET_PRIVATE_KEY");
        address deployerAddress = vm.rememberKey(deployerKey);

        vm.startBroadcast(deployerAddress);

        EulaunchLens eulaunchLens = new EulaunchLens(eulaunch, eulerSwapPeriphery);
        console.log("EulaunchLens deployed at", address(eulaunchLens));

        vm.stopBroadcast();
    }
}
