// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {USDTVault} from "../src/vault.sol";
import {InitProtocolAdapter} from "../src/initAdapter.sol";
import {VaultManager} from "../src/manager.sol";
import {console} from "forge-std/console.sol";

contract DeployScript is Script {
    // Deployment addresses
    address public deployer;
    address public owner;
    address public keeper;
    address public usdt;
    
    // Protocol addresses (these need to be set for mainnet)
    address public initCore;
    address public lendingPool;
    
    // Deployed contracts
    USDTVault public vault;
    InitProtocolAdapter public initAdapter;
    VaultManager public manager;

    function setUp() public {
        deployer = vm.envAddress("DEPLOYER");
        owner = vm.envAddress("OWNER");
        keeper = vm.envAddress("KEEPER");
        usdt = vm.envAddress("USDT");
        initCore = vm.envAddress("INIT_CORE");
        lendingPool = vm.envAddress("LENDING_POOL");
    }

    function run() public {
        vm.startBroadcast(deployer);

        console.log("=== Starting Deployment ===");
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
        vm.stopBroadcast();
        vm.startBroadcast(owner);
        manager.setVault(address(vault));
        manager.setKeeper(keeper);
        manager.setAdapter(usdt, address(initAdapter));
        console.log("VaultManager configured");

        // Step 5: Configure Vault
        console.log("\n5. Configuring Vault...");
        manager.setVaultAdapter(address(initAdapter), true);
        console.log("Vault configured");

        vm.stopBroadcast();

        console.log("\n=== Deployment Complete ===");
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

    // Function to verify deployment
    function verifyDeployment() public view {
        console.log("\n=== Deployment Verification ===");
        
        // Check vault configuration
        require(vault.manager() == address(manager), "Vault manager mismatch");
        require(vault.USDT() == usdt, "Vault USDT mismatch");
        require(vault.isAdapter(address(initAdapter)), "Adapter not set in vault");
        
        // Check adapter configuration
        require(initAdapter.vault() == address(vault), "Adapter vault mismatch");
        require(address(initAdapter.initCore()) == initCore, "Adapter initCore mismatch");
        require(address(initAdapter.lendingPool()) == lendingPool, "Adapter lendingPool mismatch");
        
        // Check manager configuration
        require(manager.vault() == vault, "Manager vault mismatch");
        require(manager.keeper() == keeper, "Manager keeper mismatch");
        require(manager.getAdapter(usdt) == address(initAdapter), "Manager adapter mismatch");
        
        console.log("All configurations verified successfully!");
    }
}

// Interfaces for verification
interface IInitCore {
    function mintTo(address _pool, address _to) external returns (uint256 shares);
    function burnTo(address _pool, address _to) external returns (uint256 amount);
}

interface ILendingPool {
    function underlyingToken() external view returns (address);
    function toSharesCurrent(uint256 amount) external view returns (uint256);
    function toAmt(uint256 shares) external view returns (uint256);
} 