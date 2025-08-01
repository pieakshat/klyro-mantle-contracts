// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {VaultManager} from "../src/manager.sol";
import {USDTVault} from "../src/vault.sol";
import {InitProtocolAdapter} from "../src/initAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAdapter} from "../src/interfaces/IAdapter.sol";
import {IInitCore} from "../src/interfaces/IInitCore.sol";
import {ILendingPool} from "../src/interfaces/ILendingPool.sol";

// Mock USDT token for testing
contract MockUSDT {
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

// Mock Lending Pool (inToken)
contract MockLendingPool {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address public underlyingToken;
    uint256 public exchangeRate = 1e18; // 1:1 initially
    uint256 public totalSupply;
    
    string public name = "Mock inToken";
    string public symbol = "inUSDT";
    uint8 public decimals = 6;

    constructor(address _underlyingToken) {
        underlyingToken = _underlyingToken;
    }

    function mint(address to, uint256 amount) external returns (uint256 shares) {
        shares = (amount * 1e18) / exchangeRate;
        balanceOf[to] += shares;
        totalSupply += shares;
        return shares;
    }

    function burn(address from, uint256 shares) external returns (uint256 amount) {
        amount = (shares * exchangeRate) / 1e18;
        require(balanceOf[from] >= shares, "Insufficient balance");
        require(MockUSDT(underlyingToken).balanceOf(address(this)) >= amount, "Insufficient underlying");
        
        balanceOf[from] -= shares;
        totalSupply -= shares;
        
        // Transfer underlying tokens to the caller
        MockUSDT(underlyingToken).transfer(msg.sender, amount);
        
        return amount;
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

    function toSharesCurrent(uint256 amount) external view returns (uint256) {
        return (amount * 1e18) / exchangeRate;
    }

    function toAmt(uint256 shares) external view returns (uint256) {
        return (shares * exchangeRate) / 1e18;
    }

    // Rate functions for APY calculations
    uint256 private supplyRatePerSec = 0;
    uint256 private borrowRatePerSec = 0;

    function getSupplyRate_e18() external view returns (uint256) {
        return supplyRatePerSec;
    }

    function getBorrowRate_e18() external view returns (uint256) {
        return borrowRatePerSec;
    }

    function setSupplyRate(uint256 newRate) external {
        supplyRatePerSec = newRate;
    }

    function setBorrowRate(uint256 newRate) external {
        borrowRatePerSec = newRate;
    }

    // Simulate interest accrual
    function simulateInterest(uint256 newRate) external {
        exchangeRate = newRate;
    }
}

// Mock InitCore
contract MockInitCore {
    MockLendingPool public lendingPool;
    MockUSDT public underlyingToken;

    constructor(address _lendingPool, address _underlyingToken) {
        lendingPool = MockLendingPool(_lendingPool);
        underlyingToken = MockUSDT(_underlyingToken);
    }

    function mintTo(address _pool, address _to) external returns (uint256 shares) {
        require(_pool == address(lendingPool), "Invalid pool");
        
        // Get the amount from the lending pool's balance (tokens were transferred here)
        uint256 amount = underlyingToken.balanceOf(address(lendingPool));
        
        // Mint shares to the adapter
        shares = lendingPool.mint(_to, amount);
        
        return shares;
    }

    function burnTo(address _pool, address _to) external returns (uint256 amount) {
        require(_pool == address(lendingPool), "Invalid pool");
        
        // Get the inToken balance from the lending pool (shares were transferred here)
        uint256 shares = lendingPool.balanceOf(address(lendingPool));
        
        // Burn shares and get underlying
        amount = lendingPool.burn(address(lendingPool), shares);
        
        // Transfer underlying to the target
        underlyingToken.transfer(_to, amount);
        
        return amount;
    }
}

contract ManagerTest is Test {
    VaultManager public manager;
    USDTVault public vault;
    InitProtocolAdapter public initAdapter;
    MockUSDT public usdt;
    MockLendingPool public lendingPool;
    MockInitCore public initCore;
    
    address public owner = address(0x1);
    address public keeper = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);
    
    uint256 public constant INITIAL_BALANCE = 10000 * 1e6; // 10,000 USDT
    uint256 public constant DEPOSIT_AMOUNT = 1000 * 1e6; // 1,000 USDT

    function setUp() public {
        // Deploy mock USDT
        usdt = new MockUSDT();
        
        // Deploy mock lending pool
        lendingPool = new MockLendingPool(address(usdt));
        
        // Deploy mock InitCore
        initCore = new MockInitCore(address(lendingPool), address(usdt));
        
        // Deploy manager first
        manager = new VaultManager(address(usdt), owner);
        
        // Deploy vault with manager as the initial manager
        vault = new USDTVault(address(usdt), address(manager));
        
        // Deploy InitProtocolAdapter
        initAdapter = new InitProtocolAdapter(
            address(vault),
            address(initCore),
            address(lendingPool)
        );
        
        // Setup initial balances
        usdt.mint(user1, INITIAL_BALANCE);
        usdt.mint(user2, INITIAL_BALANCE);
        usdt.mint(address(vault), INITIAL_BALANCE);
        
        // Setup manager first
        vm.prank(owner);
        manager.setVault(address(vault));
        
        vm.prank(owner);
        manager.setKeeper(keeper);
        
        vm.prank(owner);
        manager.setAdapter(address(usdt), address(initAdapter));
        
        // Now setup adapter in vault using the manager
        vm.prank(address(manager));
        vault.setAdapter(address(initAdapter), true);
    }

    function test_ManagerConstructor() public {
        assertEq(manager.USDT(), address(usdt));
        assertEq(manager.owner(), owner);
    }

    function test_SetVault() public {
        vm.prank(owner);
        manager.setVault(address(vault));
        
        assertEq(address(manager.vault()), address(vault));
    }

    function test_SetKeeper() public {
        address newKeeper = address(0x5);
        
        vm.prank(owner);
        manager.setKeeper(newKeeper);
        
        assertEq(manager.keeper(), newKeeper);
    }

    function test_SetAdapter() public {
        address newAdapter = address(0x6);
        
        vm.prank(owner);
        manager.setAdapter(address(usdt), newAdapter);
        
        assertEq(manager.getAdapter(address(usdt)), newAdapter);
        assertTrue(manager.hasAdapter(address(usdt)));
    }

    function test_DepositToAdapter() public {
        // User deposits to vault first
        vm.startPrank(user1);
        usdt.approve(address(vault), DEPOSIT_AMOUNT);
        vault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // Keeper deposits to adapter
        uint256 depositAmount = 500 * 1e6;
        vm.prank(keeper);
        manager.depositToAdapter(address(usdt), depositAmount);
        
        // Check adapter has inTokens
        assertGt(lendingPool.balanceOf(address(initAdapter)), 0);
    }

    function test_WithdrawFromAdapter() public {
        // Setup: vault has tokens and adapter has inTokens
        usdt.mint(address(vault), 1000 * 1e6);
        
        // Keeper deposits to adapter first
        vm.prank(keeper);
        manager.depositToAdapter(address(usdt), 1000 * 1e6);
        
        // Keeper withdraws from adapter
        uint256 withdrawAmount = 300 * 1e6;
        vm.prank(keeper);
        manager.withdrawFromAdapter(address(usdt), withdrawAmount);
        
        // Check vault received tokens
        assertGt(usdt.balanceOf(address(vault)), INITIAL_BALANCE);
    }

    function test_RevertWhenNotKeeper() public {
        vm.expectRevert(VaultManager.NotKeeper.selector);
        manager.depositToAdapter(address(usdt), 1000 * 1e6);
    }

    function test_RevertWhenNotOwner() public {
        vm.expectRevert();
        manager.setVault(address(0x5));
    }

    function test_RevertWhenZeroAmount() public {
        vm.prank(keeper);
        vm.expectRevert(VaultManager.ZeroAmount.selector);
        manager.depositToAdapter(address(usdt), 0);
    }

    function test_RevertWhenAdapterNotSet() public {
        vm.prank(keeper);
        vm.expectRevert(VaultManager.AdapterNotSet.selector);
        manager.depositToAdapter(address(0x5), 1000 * 1e6);
    }

    function test_PauseUnpause() public {
        vm.prank(owner);
        manager.pause();
        
        vm.prank(keeper);
        vm.expectRevert();
        manager.depositToAdapter(address(usdt), 1000 * 1e6);
        
        vm.prank(owner);
        manager.unpause();
        
        // Should work again
        vm.prank(keeper);
        manager.depositToAdapter(address(usdt), 1000 * 1e6);
    }

    function test_OwnerCanActAsKeeper() public {
        // Owner should be able to act as keeper
        vm.prank(owner);
        manager.depositToAdapter(address(usdt), 1000 * 1e6);
        
        // Should not revert
        assertTrue(true);
    }
} 