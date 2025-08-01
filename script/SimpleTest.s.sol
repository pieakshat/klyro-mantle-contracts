// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {USDTVault} from "../src/vault.sol";
import {VaultManager} from "../src/manager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

contract SimpleTestScript is Script {
    // Deployed contract addresses (from previous deployment)
    address public constant VAULT_MANAGER = 0x922D6956C99E12DFeB3224DEA977D0939758A1Fe;
    address public constant USDT_VAULT = 0x5081a39b8A5f0E35a8D959395a630b68B74Dd30f;
    address public constant USDT = 0x201eBA5cC46D216ce6DC03f6A759e8E7660e1BBc;
    
    // Test user (using account 0 which has ETH)
    address public constant TEST_USER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public constant KEEPER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    
    // Contract instances
    VaultManager public manager;
    USDTVault public vault;
    IERC20 public usdt;

    function setUp() public {
        manager = VaultManager(VAULT_MANAGER);
        vault = USDTVault(USDT_VAULT);
        usdt = IERC20(USDT);
    }

    function run() public {
        console.log("=== Simple Test Script ===");
        console.log("Test User:", TEST_USER);
        console.log("Keeper:", KEEPER);
        console.log("USDT Balance (User):", usdt.balanceOf(TEST_USER));
        console.log("Vault Total Assets:", vault.totalAssets());
        console.log("Vault Total Shares:", vault.totalShares());
        console.log("Vault Manager:", vault.manager());
        console.log("Manager Vault:", address(manager.vault()));
        console.log("Manager Keeper:", manager.keeper());
        
        // Test 1: Check if USDT contract exists and has basic functionality
        console.log("\n=== Test 1: USDT Contract Check ===");
        console.log("USDT Contract Code Length:", address(usdt).code.length);
        
        // Test basic ERC20 functions
        try usdt.balanceOf(TEST_USER) returns (uint256 balance) {
            console.log("USDT balanceOf() works, balance:", balance);
        } catch {
            console.log("USDT balanceOf() call failed");
        }
        
        // Test 2: Check vault configuration
        console.log("\n=== Test 2: Vault Configuration ===");
        console.log("Vault USDT:", vault.USDT());
        console.log("Vault Reserve BPS:", vault.reserveBps());
        console.log("Vault Adapters Length:", vault.adaptersLength());
        
        // Test 3: Check manager configuration
        console.log("\n=== Test 3: Manager Configuration ===");
        console.log("Manager USDT:", manager.USDT());
        console.log("Manager has USDT adapter:", manager.hasAdapter(USDT));
        
        // Test 4: Try to deposit if user has USDT
        console.log("\n=== Test 4: Deposit Test ===");
        uint256 userBalance = usdt.balanceOf(TEST_USER);
        console.log("User USDT Balance:", userBalance);
        
        if (userBalance > 0) {
            uint256 depositAmount = 100 * 1e6; // 100 USDT (assuming 6 decimals)
            
            if (userBalance >= depositAmount) {
                vm.startBroadcast(TEST_USER);
                
                // Approve USDT spending
                usdt.approve(address(vault), depositAmount);
                console.log("USDT approved for vault");
                
                // Deposit into vault
                vault.deposit(depositAmount);
                console.log("Deposited", depositAmount / 1e6, "USDT into vault");
                
                vm.stopBroadcast();
                
                console.log("User shares after deposit:", vault.shares(TEST_USER));
                console.log("Vault total shares:", vault.totalShares());
                console.log("Vault total assets:", vault.totalAssets());
            } else {
                console.log("User doesn't have enough USDT for deposit");
            }
        } else {
            console.log("User has no USDT balance");
        }
        
        console.log("\n=== Test Complete ===");
    }
} 