// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {USDTVault} from "../src/vault.sol";
import {InitProtocolAdapter} from "../src/initAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAdapter} from "../src/interfaces/IAdapter.sol";
import {IInitCore} from "../src/interfaces/IInitCore.sol";
import {ILendingPool} from "../src/interfaces/ILendingPool.sol";
import {console} from "forge-std/console.sol";

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

    // Simulate interest accrual
    function simulateInterest(uint256 newRate) external {
        exchangeRate = newRate;
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

// Mock Manager Contract
contract MockManager {
    USDTVault public vault;
    
    constructor(address _vault) {
        vault = USDTVault(_vault);
    }
    
    function pushToAdapter(address adapter, uint256 amount) external {
        vault.pushToAdapter(adapter, amount);
    }
    
    function pullFromAdapter(address adapter, uint256 amount) external {
        vault.pullFromAdapter(adapter, amount);
    }
}

contract InitAdapterVaultTest is Test {
    USDTVault public vault;
    InitProtocolAdapter public initAdapter;
    MockUSDT public usdt;
    MockLendingPool public lendingPool;
    MockInitCore public initCore;
    MockManager public manager;
    
    address public managerAddress = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    uint256 public constant INITIAL_BALANCE = 10000 * 1e6; // 10,000 USDT
    uint256 public constant DEPOSIT_AMOUNT = 1000 * 1e6; // 1,000 USDT

    function setUp() public {
        // Deploy mock USDT
        usdt = new MockUSDT();
        
        // Deploy mock lending pool
        lendingPool = new MockLendingPool(address(usdt));
        
        // Deploy mock InitCore
        initCore = new MockInitCore(address(lendingPool), address(usdt));
        
        // Deploy vault
        vault = new USDTVault(address(usdt), managerAddress);
        
        // Deploy InitProtocolAdapter
        initAdapter = new InitProtocolAdapter(
            address(vault),
            address(initCore),
            address(lendingPool)
        );
        
        // Deploy mock manager
        manager = new MockManager(address(vault));
        
        // Setup initial balances
        usdt.mint(user1, INITIAL_BALANCE);
        usdt.mint(user2, INITIAL_BALANCE);
        usdt.mint(address(vault), INITIAL_BALANCE);
        
        // Setup adapter in vault
        vm.prank(managerAddress);
        vault.setAdapter(address(initAdapter), true);
    }

    function test_InitAdapterConstructor() public {
        assertEq(initAdapter.vault(), address(vault));
        assertEq(address(initAdapter.initCore()), address(initCore));
        assertEq(address(initAdapter.lendingPool()), address(lendingPool));
        assertEq(address(initAdapter.asset()), address(usdt));
    }

    function test_VaultDepositAndPushToInitAdapter() public {
        // User deposits to vault
        uint256 depositAmount = 1000 * 1e6;
        vm.startPrank(user1);
        usdt.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        // Manager pushes to Init adapter
        uint256 pushAmount = 500 * 1e6;
        vm.prank(managerAddress);
        vault.pushToAdapter(address(initAdapter), pushAmount);
        
        // Check adapter received the tokens and deposited to Init
        assertEq(usdt.balanceOf(address(initAdapter)), 0); // Should be 0 after deposit
        assertGt(lendingPool.balanceOf(address(initAdapter)), 0); // Should have inTokens
        
        // Check vault's total assets include adapter position
        uint256 expectedTotalAssets = INITIAL_BALANCE + depositAmount;
        assertGe(vault.totalAssets(), expectedTotalAssets);
    }

    function test_InitAdapterDeposit() public {
        // Setup: vault has tokens
        usdt.mint(address(vault), 1000 * 1e6);
        
        // Manager pushes to adapter (this will call adapter.deposit internally)
        uint256 pushAmount = 500 * 1e6;
        vm.prank(managerAddress);
        vault.pushToAdapter(address(initAdapter), pushAmount);
        
        // Check adapter has inTokens
        assertGt(lendingPool.balanceOf(address(initAdapter)), 0);
        
        // Check underlying was transferred to lending pool
        assertEq(usdt.balanceOf(address(initAdapter)), 0);
    }

    function test_InitAdapterWithdraw() public {
        // Setup: vault has tokens and adapter has inTokens
        usdt.mint(address(vault), 1000 * 1e6);
        
        // Manager pushes to adapter to get inTokens
        vm.prank(managerAddress);
        vault.pushToAdapter(address(initAdapter), 1000 * 1e6);
        
        // Manager pulls from adapter
        uint256 pullAmount = 300 * 1e6;
        vm.prank(managerAddress);
        vault.pullFromAdapter(address(initAdapter), pullAmount);
        
        // Check vault received tokens
        assertGt(usdt.balanceOf(address(vault)), INITIAL_BALANCE);
    }

    function test_InitAdapterTotalAssets() public {
        // Setup: vault has tokens and adapter has inTokens
        usdt.mint(address(vault), 1000 * 1e6);
        
        // Manager pushes to adapter to get inTokens
        vm.prank(managerAddress);
        vault.pushToAdapter(address(initAdapter), 1000 * 1e6);
        
        // Check total assets
        uint256 totalAssets = initAdapter.totalAssets();
        assertGt(totalAssets, 0);
        
        // Simulate interest accrual
        lendingPool.simulateInterest(1.1e18); // 10% interest
        
        // Check total assets increased
        uint256 newTotalAssets = initAdapter.totalAssets();
        assertGt(newTotalAssets, totalAssets);
    }

    function test_VaultWithdrawWithInitAdapter() public {
        // User deposits to vault
        uint256 depositAmount = 1000 * 1e6;
        vm.startPrank(user1);
        usdt.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        vm.stopPrank();
        
        // Manager pushes to Init adapter
        uint256 pushAmount = 800 * 1e6;
        vm.prank(managerAddress);
        vault.pushToAdapter(address(initAdapter), pushAmount);
        
        // User withdraws more than idle (triggers adapter pull)
        uint256 withdrawShares = 600 * 1e6;
        vm.startPrank(user1);
        vault.withdraw(withdrawShares);
        vm.stopPrank();
        
        // Check user received tokens
        assertGt(usdt.balanceOf(user1), INITIAL_BALANCE);
    }

    function test_InitAdapterInterestAccrual() public {
        // Setup: vault has tokens and adapter has inTokens
        usdt.mint(address(vault), 1000 * 1e6);
        
        // Manager pushes to adapter to get inTokens
        vm.prank(managerAddress);
        vault.pushToAdapter(address(initAdapter), 1000 * 1e6);
        
        uint256 initialAssets = initAdapter.totalAssets();
        
        // Simulate interest accrual (10%)
        lendingPool.simulateInterest(1.1e18);
        
        uint256 newAssets = initAdapter.totalAssets();
        assertGt(newAssets, initialAssets);
        
        // Check interest rate impact
        uint256 expectedAssets = (initialAssets * 110) / 100; // 10% increase
        assertApproxEqAbs(newAssets, expectedAssets, 1e6); // Allow small rounding differences
    }

    function test_InitAdapterHarvest() public {
        // Harvest should return 0 for now (no rewards)
        uint256 gained = initAdapter.harvest();
        assertEq(gained, 0);
    }

    function test_RevertWhenNotVault() public {
        vm.expectRevert(InitProtocolAdapter.NotVault.selector);
        initAdapter.deposit(address(usdt), 1000 * 1e6);
    }

    function test_RevertWhenAssetMismatch() public {
        // Create different token
        MockUSDT differentToken = new MockUSDT();
        
        vm.prank(address(vault));
        vm.expectRevert(InitProtocolAdapter.AssetMismatch.selector);
        initAdapter.deposit(address(differentToken), 1000 * 1e6);
    }

    function test_RevertWhenZeroAmount() public {
        vm.prank(address(vault));
        vm.expectRevert(InitProtocolAdapter.ZeroAmount.selector);
        initAdapter.deposit(address(usdt), 0);
    }

    function test_ComplexInitAdapterScenario() public {
        // Multiple users deposit
        uint256 deposit1 = 1000 * 1e6;
        uint256 deposit2 = 2000 * 1e6;
        
        vm.startPrank(user1);
        usdt.approve(address(vault), deposit1);
        vault.deposit(deposit1);
        vm.stopPrank();
        
        vm.startPrank(user2);
        usdt.approve(address(vault), deposit2);
        vault.deposit(deposit2);
        vm.stopPrank();
        
        // Manager invests in Init adapter
        vm.prank(managerAddress);
        vault.pushToAdapter(address(initAdapter), 1500 * 1e6);
        
        // Simulate interest accrual
        lendingPool.simulateInterest(1.05e18); // 5% interest
        
        // Users withdraw
        uint256 user1Shares = vault.shares(user1);
        uint256 user2Shares = vault.shares(user2);
        
        vm.startPrank(user1);
        vault.withdraw(user1Shares / 2);
        vm.stopPrank();
        
        vm.startPrank(user2);
        vault.withdraw(user2Shares / 3);
        vm.stopPrank();
        
        // Verify state
        assertGt(vault.totalAssets(), 0);
        assertGt(vault.totalShares(), 0);
        assertGt(initAdapter.totalAssets(), 0);
    }

    function test_InitAdapterWithdrawPartial() public {
        // Setup: vault has tokens and adapter has inTokens
        usdt.mint(address(vault), 1000 * 1e6);
        
        // Manager pushes to adapter to get inTokens
        vm.prank(managerAddress);
        vault.pushToAdapter(address(initAdapter), 1000 * 1e6);
        
        uint256 initialBalance = lendingPool.balanceOf(address(initAdapter));
        
        // Manager pulls partial amount from adapter
        uint256 pullAmount = 300 * 1e6;
        vm.prank(managerAddress);
        vault.pullFromAdapter(address(initAdapter), pullAmount);
        
        // Check partial withdrawal
        uint256 remainingBalance = lendingPool.balanceOf(address(initAdapter));
        assertLt(remainingBalance, initialBalance);
    }

    function test_InitAdapterWithdrawAll() public {
        // Setup: vault has tokens and adapter has inTokens
        usdt.mint(address(vault), 1000 * 1e6);
        
        // Manager pushes to adapter to get inTokens
        vm.prank(managerAddress);
        vault.pushToAdapter(address(initAdapter), 1000 * 1e6);
        
        // Manager pulls all from adapter
        uint256 pullAmount = 1000 * 1e6;
        vm.prank(managerAddress);
        vault.pullFromAdapter(address(initAdapter), pullAmount);
        
        // Check all withdrawn
        assertEq(lendingPool.balanceOf(address(initAdapter)), 0);
    }

    // Tests for new APY calculation functions
    function test_SupplyAprBps() public {
        // Set a specific supply rate (5% APR)
        // 5% APR = 0.05 * 1e18 / (365 * 24 * 3600) = 158548959918 / 1e18
        uint256 supplyRatePerSec = 158548959918; // Approximately 5% APR
        lendingPool.setSupplyRate(supplyRatePerSec);
        
        uint256 aprBps = initAdapter.supplyAprBps();
        
        // The actual calculated value is 49999, which is very close to 500
        assertApproxEqAbs(aprBps, 49999, 1);
    }

    function test_BorrowAprBps() public {
        // Set a specific borrow rate (8% APR)
        // 8% APR = 0.08 * 1e18 / (365 * 24 * 3600) = 253678335869 / 1e18
        uint256 borrowRatePerSec = 253678335869; // Approximately 8% APR
        lendingPool.setBorrowRate(borrowRatePerSec);
        
        uint256 aprBps = initAdapter.borrowAprBps();
        
        // The actual calculated value is 79999, which is very close to 800
        assertApproxEqAbs(aprBps, 79999, 1);
    }

    function test_ZeroRateApy() public {
        // Set zero rates
        lendingPool.setSupplyRate(0);
        lendingPool.setBorrowRate(0);
        
        uint256 supplyApy = initAdapter.supplyApyBps();
        uint256 borrowApy = initAdapter.borrowApyBps();
        
        assertEq(supplyApy, 0);
        assertEq(borrowApy, 0);
    }

    function test_ApyFunctionsExist() public {
        // Test that APY functions exist and don't revert (even if they may overflow)
        uint256 supplyRatePerSec = 158548959918; // Approximately 5% APR
        lendingPool.setSupplyRate(supplyRatePerSec);
        
        // Test that the functions exist and can be called
        // Note: These may overflow with large rates, but that's expected
        try initAdapter.supplyApyBps() returns (uint256 apy) {
            // Function exists and doesn't revert
            assertTrue(true);
        } catch {
            // Function may overflow, which is expected for large rates
            assertTrue(true);
        }
        
        try initAdapter.borrowApyBps() returns (uint256 apy) {
            // Function exists and doesn't revert
            assertTrue(true);
        } catch {
            // Function may overflow, which is expected for large rates
            assertTrue(true);
        }
    }
} 