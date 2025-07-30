// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {USDTVault} from "../src/vault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAdapter} from "../src/interfaces/Iadapter.sol";

// Mock ERC20 token for testing
contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    string public name = "Mock USDT";
    string public symbol = "USDT";
    uint8 public decimals = 6;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

// Mock adapter for testing
contract MockAdapter is IAdapter {
    mapping(address => uint256) public deposited;
    mapping(address => uint256) public totalAssetsValue;
    address public vault;
    address public usdtAddress;

    constructor(address _vault) {
        vault = _vault;
    }

    function setUsdtAddress(address _usdt) external {
        usdtAddress = _usdt;
    }

    function deposit(address asset, uint256 amount) external returns (uint256) {
        require(msg.sender == vault, "Only vault can deposit");
        deposited[asset] += amount;
        totalAssetsValue[asset] += amount;
        return amount;
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        require(msg.sender == vault, "Only vault can withdraw");
        require(deposited[asset] >= amount, "Insufficient deposited");
        deposited[asset] -= amount;
        totalAssetsValue[asset] -= amount;
        
        // Simulate transfer back to vault
        MockERC20(asset).transfer(to, amount);
        return amount;
    }

    function totalAssets() external view returns (uint256) {
        // Return the total assets for the USDT token
        return totalAssetsValue[usdtAddress];
    }

    function harvest() external returns (uint256 gained) {
        // Simulate some yield
        uint256 yield = totalAssetsValue[usdtAddress] / 100; // 1% yield
        totalAssetsValue[usdtAddress] += yield;
        return yield;
    }

    // Helper function to simulate yield
    function simulateYield(uint256 yield) external {
        totalAssetsValue[usdtAddress] += yield;
    }
}

contract VaultTest is Test {
    USDTVault public vault;
    MockERC20 public usdt;
    MockAdapter public adapter1;
    MockAdapter public adapter2;
    
    address public manager = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    uint256 public constant INITIAL_BALANCE = 1000 * 1e6; // 1000 USDT
    uint256 public constant DEPOSIT_AMOUNT = 100 * 1e6; // 100 USDT

    function setUp() public {
        // Deploy mock USDT
        usdt = new MockERC20();
        
        // Deploy vault
        vault = new USDTVault(address(usdt), manager);
        
        // Deploy mock adapters
        adapter1 = new MockAdapter(address(vault));
        adapter2 = new MockAdapter(address(vault));
        
        // Set USDT address in adapters
        adapter1.setUsdtAddress(address(usdt));
        adapter2.setUsdtAddress(address(usdt));
        
        // Setup initial balances
        usdt.mint(user1, INITIAL_BALANCE);
        usdt.mint(user2, INITIAL_BALANCE);
        usdt.mint(address(vault), INITIAL_BALANCE);
        
        // Mint tokens to adapters for withdrawals
        usdt.mint(address(adapter1), INITIAL_BALANCE);
        usdt.mint(address(adapter2), INITIAL_BALANCE);
        
        // Setup adapters in vault
        vm.prank(manager);
        vault.setAdapter(address(adapter1), true);
        vm.prank(manager);
        vault.setAdapter(address(adapter2), true);
    }

    function test_Constructor() public {
        assertEq(vault.USDT(), address(usdt));
        assertEq(vault.manager(), manager);
        assertEq(vault.reserveBps(), 100); // 1%
    }

    function test_SetManager() public {
        address newManager = address(0x4);
        vm.prank(manager);
        vault.setManager(newManager);
        assertEq(vault.manager(), newManager);
    }

    function test_SetAdapter() public {
        address newAdapter = address(0x5);
        vm.prank(manager);
        vault.setAdapter(newAdapter, true);
        assertTrue(vault.isAdapter(newAdapter));
        assertEq(vault.adaptersLength(), 3); // 2 from setUp + 1 new
    }

    function test_SetReserveBps() public {
        vm.prank(manager);
        vault.setReserveBps(500); // 5%
        assertEq(vault.reserveBps(), 500);
    }

    function test_Deposit() public {
        uint256 depositAmount = 100 * 1e6;
        
        vm.startPrank(user1);
        usdt.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        assertEq(vault.shares(user1), depositAmount); // 1:1 ratio initially
        assertEq(vault.totalShares(), depositAmount);
        assertEq(usdt.balanceOf(address(vault)), INITIAL_BALANCE + depositAmount);
    }

    function test_Withdraw() public {
        // First deposit
        uint256 depositAmount = 100 * 1e6;
        vm.startPrank(user1);
        usdt.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        
        // Then withdraw
        uint256 sharesToBurn = 50 * 1e6;
        vault.withdraw(sharesToBurn);
        vm.stopPrank();
        
        assertEq(vault.shares(user1), depositAmount - sharesToBurn);
        assertEq(vault.totalShares(), depositAmount - sharesToBurn);
    }

    function test_PushToAdapter() public {
        uint256 pushAmount = 50 * 1e6;
        
        vm.prank(manager);
        vault.pushToAdapter(address(adapter1), pushAmount);
        
        assertEq(adapter1.deposited(address(usdt)), pushAmount);
        assertEq(adapter1.totalAssets(), pushAmount);
    }

    function test_PullFromAdapter() public {
        // First push to adapter
        uint256 pushAmount = 50 * 1e6;
        vm.prank(manager);
        vault.pushToAdapter(address(adapter1), pushAmount);
        
        // Then pull from adapter
        uint256 pullAmount = 20 * 1e6;
        vm.prank(manager);
        vault.pullFromAdapter(address(adapter1), pullAmount);
        
        assertEq(adapter1.deposited(address(usdt)), pushAmount - pullAmount);
    }

    function test_TotalAssets() public {
        uint256 initialAssets = vault.totalAssets();
        assertEq(initialAssets, INITIAL_BALANCE);
        
        // Push to adapter
        uint256 pushAmount = 50 * 1e6;
        vm.prank(manager);
        vault.pushToAdapter(address(adapter1), pushAmount);
        
        uint256 newAssets = vault.totalAssets();
        // Total assets should include both vault balance and adapter assets
        assertEq(newAssets, initialAssets + pushAmount);
    }

    function test_ConvertToShares() public {
        uint256 assets = 100 * 1e6;
        uint256 shares = vault.convertToShares(assets);
        assertEq(shares, assets); // 1:1 ratio initially
    }

    function test_ConvertToAssets() public {
        uint256 shares = 100 * 1e6;
        uint256 assets = vault.convertToAssets(shares);
        assertEq(assets, 0); // When totalShares is 0, convertToAssets returns 0
    }

    function test_IdleTarget() public {
        uint256 target = vault.idleTarget();
        uint256 totalAssets = vault.totalAssets();
        assertEq(target, (totalAssets * 100) / 10000); // 1% of total assets
    }

    function test_WithdrawWithAdapterPull() public {
        // Deposit
        uint256 depositAmount = 100 * 1e6;
        vm.startPrank(user1);
        usdt.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        
        // Push to adapter (reducing idle)
        vm.stopPrank();
        vm.prank(manager);
        vault.pushToAdapter(address(adapter1), 80 * 1e6);
        
        // Withdraw more than idle
        vm.startPrank(user1);
        vault.withdraw(50 * 1e6);
        vm.stopPrank();
    }

    function test_RevertWhenNotManager() public {
        vm.expectRevert(USDTVault.NotManager.selector);
        vault.setManager(address(0x4));
    }

    function test_RevertWhenInvalidAdapter() public {
        vm.expectRevert(USDTVault.InvalidAdapter.selector);
        vm.prank(manager);
        vault.pushToAdapter(address(0x5), 100 * 1e6);
    }

    function test_RevertWhenZeroAmount() public {
        vm.expectRevert(USDTVault.ZeroAmount.selector);
        vault.deposit(0);
    }

    function test_RevertWhenInsufficientShares() public {
        vm.expectRevert(USDTVault.InsufficientShares.selector);
        vault.withdraw(100 * 1e6);
    }

    function test_RevertWhenKeepReserve() public {
        // Try to push more than available (respecting reserve)
        vm.expectRevert(USDTVault.KeepReserve.selector);
        vm.prank(manager);
        vault.pushToAdapter(address(adapter1), INITIAL_BALANCE);
    }

    function test_MultipleUsers() public {
        // User1 deposits
        uint256 deposit1 = 100 * 1e6;
        vm.startPrank(user1);
        usdt.approve(address(vault), deposit1);
        vault.deposit(deposit1);
        vm.stopPrank();
        
        // User2 deposits
        uint256 deposit2 = 200 * 1e6;
        vm.startPrank(user2);
        usdt.approve(address(vault), deposit2);
        vault.deposit(deposit2);
        vm.stopPrank();
        
        // When totalShares is 0 initially, shares are 1:1 with assets
        assertEq(vault.shares(user1), deposit1);
        // User2 gets shares based on the formula: (assets * totalShares) / totalAssets
        // totalAssets = INITIAL_BALANCE + deposit1 + deposit2 = 1000 + 100 + 200 = 1300
        // totalShares = deposit1 = 100
        // user2 shares = (200 * 100) / 1300 = 15.38
        uint256 totalAssetsAfterFirstDeposit = INITIAL_BALANCE + deposit1;
        uint256 expectedUser2Shares = (deposit2 * deposit1) / totalAssetsAfterFirstDeposit;
        assertEq(vault.shares(user2), expectedUser2Shares);
        assertEq(vault.totalShares(), deposit1 + expectedUser2Shares);
    }

    function test_AdapterYield() public {
        // Push to adapter
        uint256 pushAmount = 100 * 1e6;
        vm.prank(manager);
        vault.pushToAdapter(address(adapter1), pushAmount);
        
        // Simulate yield
        uint256 yield = 10 * 1e6;
        adapter1.simulateYield(yield);
        
        // Check total assets increased
        uint256 newTotalAssets = vault.totalAssets();
        assertGt(newTotalAssets, INITIAL_BALANCE + pushAmount);
    }

    function test_ComplexScenario() public {
        // Setup: Multiple users, multiple adapters, yield
        uint256 deposit1 = 100 * 1e6;
        uint256 deposit2 = 200 * 1e6;
        
        // Users deposit
        vm.startPrank(user1);
        usdt.approve(address(vault), deposit1);
        vault.deposit(deposit1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdt.approve(address(vault), deposit2);
        vault.deposit(deposit2);
        vm.stopPrank();
        
        // Manager invests in adapters
        vm.prank(manager);
        vault.pushToAdapter(address(adapter1), 150 * 1e6);
        vm.prank(manager);
        vault.pushToAdapter(address(adapter2), 100 * 1e6);
        
        // Simulate yield
        adapter1.simulateYield(15 * 1e6);
        adapter2.simulateYield(10 * 1e6);
        
        // Users withdraw - use their actual share amounts
        uint256 user1Shares = vault.shares(user1);
        uint256 user2Shares = vault.shares(user2);
        
        vm.startPrank(user1);
        vault.withdraw(user1Shares / 2); // Withdraw half of user1's shares
        vm.stopPrank();
        
        vm.startPrank(user2);
        vault.withdraw(user2Shares / 2); // Withdraw half of user2's shares
        vm.stopPrank();
        
        // Verify state
        assertGt(vault.totalAssets(), 0);
        assertGt(vault.totalShares(), 0);
    }
} 