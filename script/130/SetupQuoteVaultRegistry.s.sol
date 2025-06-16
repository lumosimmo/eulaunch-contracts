// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import "forge-std/Script.sol";
import {QuoteVaultRegistry} from "src/QuoteVaultRegistry.sol";
import {EVault} from "euler-vault-kit/src/EVault/EVault.sol";

contract SetupQuoteVaultRegistry is Script {
    address public constant quoteVaultRegistry = 0x0000000000000000000000000000000000000000;

    address public constant USDC = 0x078D782b760474a361dDA0AF3839290b0EF57AD6;
    address public constant USDC_VAULT = 0x6eAe95ee783e4D862867C4e0E4c3f4B95AA682Ba;
    address public constant USDT = 0x9151434b16b9763660705744891fA906F660EcC5;
    address public constant USDT_VAULT = 0xD49181c522eCDB265f0D9C175Cf26FFACE64eAD3;
    address public constant WETH = 0x4200000000000000000000000000000000000006;
    address public constant WETH_VAULT = 0x1f3134C3f3f8AdD904B9635acBeFC0eA0D0E1ffC;
    address public constant WBTC = 0x0555E30da8f98308EdB960aa94C0Db47230d2B9c;
    address public constant WBTC_VAULT = 0x5d2511C1EBc795F4394f7f659f693f8C15796485;
    address public constant weETH = 0x7DCC39B4d1C53CB31e1aBc0e358b43987FEF80f7;
    address public constant weETH_VAULT = 0xe36DA4Ea4D07E54B1029eF26A896A656A3729f86;

    function assertVault(address token, address vault) internal view {
        require(EVault(vault).asset() == token, "Vault does not match token");
    }

    function assertVaults() internal view {
        assertVault(USDC, USDC_VAULT);
        assertVault(USDT, USDT_VAULT);
        assertVault(WETH, WETH_VAULT);
        assertVault(WBTC, WBTC_VAULT);
        assertVault(weETH, weETH_VAULT);
    }

    function run() public {
        uint256 deployerKey = vm.envUint("WALLET_PRIVATE_KEY");
        address deployerAddress = vm.rememberKey(deployerKey);

        require(quoteVaultRegistry != address(0), "QuoteVaultRegistry not set");

        vm.startBroadcast(deployerAddress);

        assertVaults();

        QuoteVaultRegistry(quoteVaultRegistry).setQuoteVault(USDC, USDC_VAULT);
        QuoteVaultRegistry(quoteVaultRegistry).setQuoteVault(USDT, USDT_VAULT);
        QuoteVaultRegistry(quoteVaultRegistry).setQuoteVault(WETH, WETH_VAULT);
        QuoteVaultRegistry(quoteVaultRegistry).setQuoteVault(WBTC, WBTC_VAULT);
        QuoteVaultRegistry(quoteVaultRegistry).setQuoteVault(weETH, weETH_VAULT);

        vm.stopBroadcast();
    }
}
