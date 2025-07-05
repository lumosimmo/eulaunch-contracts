// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import "forge-std/Script.sol";
import {PiecewiseRouter} from "src/piecewise/PiecewiseRouter.sol";

contract DeployPiecewiseRouter is Script {
    address public constant eulerSwapPeriphery = 0xdAAF468d84DD8945521Ea40297ce6c5EEfc7003a;

    function run() public {
        vm.createSelectFork("unichain");
        uint256 deployerKey = vm.envUint("WALLET_PRIVATE_KEY");
        address deployerAddress = vm.rememberKey(deployerKey);

        vm.startBroadcast(deployerAddress);

        // Deploy Piecewise Router
        PiecewiseRouter piecewiseRouter = new PiecewiseRouter(eulerSwapPeriphery);
        console.log("PiecewiseRouter deployed at", address(piecewiseRouter));

        vm.stopBroadcast();
    }
}
