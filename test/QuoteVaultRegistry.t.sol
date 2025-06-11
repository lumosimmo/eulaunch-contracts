// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {QuoteVaultRegistry} from "src/QuoteVaultRegistry.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {EulaunchTestBase} from "./EulaunchTestBase.t.sol";
import {IEVault} from "euler-vault-kit/src/EVault/IEVault.sol";
import {IRMTestDefault} from "euler-vault-kit/test/mocks/IRMTestDefault.sol";
import {EulerSwapFactory} from "euler-swap/src/EulerSwapFactory.sol";

contract QuoteVaultRegistryTest is EulaunchTestBase {
    QuoteVaultRegistry internal registry;

    function setUp() public override {
        super.setUp();

        vm.startPrank(deployer);
        registry = new QuoteVaultRegistry(address(eulerSwapFactory));
        vm.stopPrank();
    }

    function test_Constructor() public view {
        assertEq(registry.eulerSwapFactory(), address(eulerSwapFactory));
        assertEq(registry.owner(), deployer);
    }

    function test_SetQuoteVault_Success() public {
        vm.startPrank(deployer);
        registry.setQuoteVault(address(assetTST), address(eTST));
        vm.stopPrank();

        assertEq(registry.quoteVaults(address(assetTST)), address(eTST));
    }

    function test_SetQuoteVault_WhenNotOwner_ShouldRevert() public {
        vm.startPrank(user1);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.setQuoteVault(address(assetTST), address(eTST));
        vm.stopPrank();
    }

    function test_SetQuoteVault_WhenVaultDoesNotMatchToken_ShouldRevert() public {
        vm.startPrank(deployer);
        // eTST2 is a vault for assetTST2, not assetTST
        vm.expectRevert(QuoteVaultRegistry.VaultDoesNotMatchToken.selector);
        registry.setQuoteVault(address(assetTST), address(eTST2));
        vm.stopPrank();
    }

    function test_SetQuoteVault_WhenVaultIsNotValidProxy_ShouldRevert() public {
        address invalidVault = vm.addr(99);
        vm.label(invalidVault, "InvalidVault");

        vm.startPrank(deployer);
        vm.expectRevert(EulerSwapFactory.InvalidVaultImplementation.selector);
        registry.setQuoteVault(address(assetTST), invalidVault);
        vm.stopPrank();
    }

    function test_SetQuoteVault_UpdateExisting() public {
        IEVault newValidVaultForAssetTST = IEVault(
            factory.createProxy(address(0), true, abi.encodePacked(address(assetTST), address(oracle), unitOfAccount))
        );
        newValidVaultForAssetTST.setHookConfig(address(0), 0);
        newValidVaultForAssetTST.setInterestRateModel(address(new IRMTestDefault()));
        newValidVaultForAssetTST.setMaxLiquidationDiscount(0.2e4);
        newValidVaultForAssetTST.setFeeReceiver(feeReceiver);

        vm.startPrank(deployer);
        registry.setQuoteVault(address(assetTST), address(eTST));
        assertEq(registry.quoteVaults(address(assetTST)), address(eTST));

        registry.setQuoteVault(address(assetTST), address(newValidVaultForAssetTST));
        vm.stopPrank();

        assertEq(registry.quoteVaults(address(assetTST)), address(newValidVaultForAssetTST));
    }

    function test_RemoveQuoteVault_Success() public {
        vm.startPrank(deployer);
        registry.setQuoteVault(address(assetTST), address(eTST));
        assertEq(registry.quoteVaults(address(assetTST)), address(eTST), "Pre-condition failed: Vault not set");

        registry.removeQuoteVault(address(assetTST));
        vm.stopPrank();

        assertEq(registry.quoteVaults(address(assetTST)), address(0));
    }

    function test_RemoveQuoteVault_WhenNotOwner_ShouldRevert() public {
        vm.startPrank(deployer);
        registry.setQuoteVault(address(assetTST), address(eTST)); // Ensure vault exists
        vm.stopPrank();

        vm.startPrank(user1);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.removeQuoteVault(address(assetTST));
        vm.stopPrank();
    }

    function test_RemoveQuoteVault_NonExistent() public {
        assertEq(registry.quoteVaults(address(assetTST)), address(0), "Initial state should be no vault for assetTST");

        // Removing a non-existent vault should not revert
        vm.startPrank(deployer);
        registry.removeQuoteVault(address(assetTST));
        vm.stopPrank();

        assertEq(registry.quoteVaults(address(assetTST)), address(0));
    }

    function test_GetQuoteVault_Success() public {
        vm.startPrank(deployer);
        registry.setQuoteVault(address(assetTST), address(eTST));
        vm.stopPrank();

        address retrievedVault = registry.getQuoteVault(address(assetTST));
        assertEq(retrievedVault, address(eTST));
    }

    function test_Ownable_TransferOwnership_Success() public {
        vm.startPrank(deployer);
        registry.transferOwnership(user1);
        vm.stopPrank();
        assertEq(registry.owner(), user1);

        vm.startPrank(user1);
        registry.setQuoteVault(address(assetTST), address(eTST));
        vm.stopPrank();
        assertEq(registry.quoteVaults(address(assetTST)), address(eTST));
    }

    function test_Ownable_TransferOwnership_WhenNotOwner_ShouldRevert() public {
        vm.startPrank(user1);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.transferOwnership(user2);
        vm.stopPrank();
    }

    function test_Ownable_RenounceOwnership_Success() public {
        vm.startPrank(deployer);
        registry.renounceOwnership();
        vm.stopPrank();
        assertEq(registry.owner(), address(0));
    }

    function test_Ownable_RenounceOwnership_WhenNotOwner_ShouldRevert() public {
        vm.startPrank(user1);
        vm.expectRevert(Ownable.Unauthorized.selector);
        registry.renounceOwnership();
        vm.stopPrank();
    }
}
