// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {USDTVault} from "../src/vault.sol";
import {InitProtocolAdapter} from "../src/initAdapter.sol";
import {VaultManager} from "../src/manager.sol";
import {console} from "forge-std/console.sol";

contract TestDeployScript is Script {
    // Test addresses (for local testing)
    address public deployer;
    address public owner;
    address public keeper;
    address public usdt;
    address public initCore;
    address public lendingPool;
    
    // Deployed contracts
    USDTVault public vault;
    InitProtocolAdapter public initAdapter;
    VaultManager public manager;

    function setUp() public {
        deployer = vm.addr(1);
        owner = vm.addr(2);
        keeper = vm.addr(3);
        usdt = vm.addr(4);
        initCore = vm.addr(5);
        lendingPool = vm.addr(6);
    }

    function run() public {
        vm.startBroadcast(deployer);

        console.log("=== Test Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Owner:", owner);
        console.log("Keeper:", keeper);
        console.log("USDT:", usdt);
        console.log("InitCore:", initCore);
        console.log("LendingPool:", lendingPool);

        // Step 1: Deploy VaultManager
        console.log("\n1. Deploying VaultManager...");
        manager = new VaultManager(usdt, owner);
        console.log("VaultManager deployed at:", address(manager));

        // Step 2: Deploy USDTVault with manager as initial manager
        console.log("\n2. Deploying USDTVault...");
        vault = new USDTVault(usdt, address(manager));
        console.log("USDTVault deployed at:", address(vault));

        // Step 3: Deploy InitProtocolAdapter
        console.log("\n3. Deploying InitProtocolAdapter...");
        initAdapter = new InitProtocolAdapter(
            address(vault),
            initCore,
            lendingPool
        );
        console.log("InitProtocolAdapter deployed at:", address(initAdapter));

        // Step 4: Configure VaultManager
        console.log("\n4. Configuring VaultManager...");
        manager.setVault(address(vault));
        manager.setKeeper(keeper);
        manager.setAdapter(usdt, address(initAdapter));
        console.log("VaultManager configured");

        // Step 5: Configure Vault
        console.log("\n5. Configuring Vault...");
        vault.setAdapter(address(initAdapter), true);
        console.log("Vault configured");

        vm.stopBroadcast();

        console.log("\n=== Test Deployment Complete ===");
        console.log("VaultManager:", address(manager));
        console.log("USDTVault:", address(vault));
        console.log("InitProtocolAdapter:", address(initAdapter));
        
        // Verify configuration
        console.log("\n=== Configuration Verification ===");
        console.log("Vault manager:", vault.manager());
        console.log("Vault USDT:", vault.USDT());
        console.log("Adapter vault:", initAdapter.vault());
        console.log("Adapter initCore:", address(initAdapter.initCore()));
        console.log("Adapter lendingPool:", address(initAdapter.lendingPool()));
        console.log("Manager vault:", address(manager.vault()));
        console.log("Manager keeper:", manager.keeper());
        console.log("Manager USDT adapter:", manager.getAdapter(usdt));
    }
} 