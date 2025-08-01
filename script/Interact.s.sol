// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {USDTVault} from "../src/vault.sol";
import {InitProtocolAdapter} from "../src/initAdapter.sol";
import {VaultManager} from "../src/manager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

contract InteractScript is Script {
    // Deployed contract addresses (from previous deployment)
    address public constant VAULT_MANAGER = 0x922D6956C99E12DFeB3224DEA977D0939758A1Fe;
    address public constant USDT_VAULT = 0x5081a39b8A5f0E35a8D959395a630b68B74Dd30f;
    address public constant INIT_ADAPTER = 0x1fA02b2d6A771842690194Cf62D91bdd92BfE28d;
    address public constant USDT = 0x201eBA5cC46D216ce6DC03f6A759e8E7660e1BBc;
    
    // Test user
    address public constant TEST_USER = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    address public constant KEEPER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    
    // Contract instances
    VaultManager public manager;
    USDTVault public vault;
    InitProtocolAdapter public adapter;
    IERC20 public usdt;

    function setUp() public {
        manager = VaultManager(VAULT_MANAGER);
        vault = USDTVault(USDT_VAULT);
        adapter = InitProtocolAdapter(INIT_ADAPTER);
        usdt = IERC20(USDT);
    }

    function run() public {
        console.log("=== Starting Interaction Script ===");
        console.log("Test User:", TEST_USER);
        console.log("Keeper:", KEEPER);
        console.log("USDT Balance (User):", usdt.balanceOf(TEST_USER));
        console.log("USDT Balance (Vault):", usdt.balanceOf(address(vault)));
        console.log("Vault Total Assets:", vault.totalAssets());
        console.log("Vault Total Shares:", vault.totalShares());
        
        // Step 0: Mint USDT to test user and vault
        console.log("\n=== Step 0: Minting USDT ===");
        uint256 mintAmount = 10000 * 1e6; // 10,000 USDT (6 decimals)
        
        vm.startBroadcast(TEST_USER);
        
        // Mint USDT to test user (assuming USDT has mint function)
        // Note: In a real scenario, you'd need to get USDT from a faucet or exchange
        // For this test, we'll assume the user already has some USDT or we'll use a different approach
        
        vm.stopBroadcast();
        
        // Alternative: Use a different account that might have USDT
        // Let's use account 0 which is the deployer and might have more tokens
        address userWithUSDT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        console.log("Using account with potential USDT:", userWithUSDT);
        console.log("USDT Balance (Account 0):", usdt.balanceOf(userWithUSDT));
        
        // Step 1: User deposits USDT into vault
        console.log("\n=== Step 1: User Deposits USDT ===");
        uint256 depositAmount = 1000 * 1e6; // 1000 USDT (6 decimals)
        
        vm.startBroadcast(userWithUSDT);
        
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
        console.log("USDT Balance (User):", usdt.balanceOf(TEST_USER));
        console.log("USDT Balance (Vault):", usdt.balanceOf(address(vault)));
        
        // Step 2: Keeper pushes USDT to adapter via manager
        console.log("\n=== Step 2: Keeper Pushes to Adapter ===");
        uint256 pushAmount = 500 * 1e6; // 500 USDT to push to adapter
        
        vm.startBroadcast(KEEPER);
        
        // Manager calls depositToAdapter which internally calls vault.pushToAdapter
        manager.depositToAdapter(USDT, pushAmount);
        console.log("Pushed", pushAmount / 1e6, "USDT to adapter via manager");
        
        vm.stopBroadcast();
        
        console.log("Vault total assets after push:", vault.totalAssets());
        console.log("USDT Balance (Vault):", usdt.balanceOf(address(vault)));
        console.log("Adapter total assets:", adapter.totalAssets());
        console.log("Adapter inToken balance:", IERC20(address(adapter.lendingPool())).balanceOf(address(adapter)));
        
        // Step 3: Check the flow worked correctly
        console.log("\n=== Step 3: Verification ===");
        console.log("Vault manager:", vault.manager());
        console.log("Manager vault:", address(manager.vault()));
        console.log("Manager keeper:", manager.keeper());
        console.log("Manager USDT adapter:", manager.getAdapter(USDT));
        console.log("Vault isAdapter[adapter]:", vault.isAdapter(address(adapter)));
        console.log("Adapter vault:", adapter.vault());
        
        // Step 4: Optional - Withdraw some funds back
        console.log("\n=== Step 4: Withdraw Test ===");
        uint256 withdrawShares = vault.shares(TEST_USER) / 2; // Withdraw half shares
        
        vm.startBroadcast(TEST_USER);
        vault.withdraw(withdrawShares);
        console.log("Withdrew", withdrawShares, "shares");
        vm.stopBroadcast();
        
        console.log("User shares after withdrawal:", vault.shares(TEST_USER));
        console.log("Vault total shares:", vault.totalShares());
        console.log("Vault total assets:", vault.totalAssets());
        console.log("USDT Balance (User):", usdt.balanceOf(TEST_USER));
        console.log("USDT Balance (Vault):", usdt.balanceOf(address(vault)));
        
        console.log("\n=== Interaction Complete ===");
    }
} 