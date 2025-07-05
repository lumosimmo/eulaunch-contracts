// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import "forge-std/Script.sol";
import {EulaunchOmni} from "src/omni/EulaunchOmni.sol";
import {LiquidityManagerOmni} from "src/omni/LiquidityManagerOmni.sol";

contract DeployEulaunchOmni is Script {
    address public constant evkFactory = 0xbAd8b5BDFB2bcbcd78Cc9f1573D3Aad6E865e752;
    address public constant evc = 0x2A1176964F5D7caE5406B627Bf6166664FE83c60;

    address public constant eulerSwapFactory = 0x45b146BC07c9985589B52df651310e75C6BE066A;
    address public constant eulerSwapPeriphery = 0xdAAF468d84DD8945521Ea40297ce6c5EEfc7003a;
    address public constant eulerSwapImpl = 0xd91B0bfACA4691E6Aca7E0E83D9B7F8917989a03;

    function run() public {
        vm.createSelectFork("unichain");
        uint256 deployerKey = vm.envUint("WALLET_PRIVATE_KEY");
        address deployerAddress = vm.rememberKey(deployerKey);

        vm.startBroadcast(deployerAddress);

        // Deploy Eulaunch Omni
        EulaunchOmni eulaunch = new EulaunchOmni(evc, eulerSwapFactory);
        console.log("EulaunchOmni deployed at", address(eulaunch));

        vm.stopBroadcast();
    }
}
