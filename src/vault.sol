//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; 
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAdapter} from "./interfaces/IAdapter.sol"; 

contract USDTVault is ReentrancyGuard {
    using SafeERC20 for IERC20;

    //config 
    address public immutable USDT;
    address public manager;
    uint256 public reserveBps = 100; // 1% (basis points)

    // shares accounting vars 
    uint256 public totalShares;
    mapping(address => uint256) public shares;

    // adapters
    address[] public adapters;
    mapping(address => bool) public isAdapter;

    
    event ManagerUpdated(address indexed manager);
    event AdapterSet(address indexed adapter, bool allowed);
    event Deposit(address indexed user, uint256 assets, uint256 shares);
    event Withdraw(address indexed user, uint256 assets, uint256 shares);
    event Invested(address indexed adapter, uint256 amount);
    event Divested(address indexed adapter, uint256 amount);
    event ReserveBpsUpdated(uint256 bps);

    
    error NotManager();
    error InvalidAdapter();
    error ZeroAddress();
    error ZeroAmount();
    error InsufficientShares();
    error KeepReserve();
    error InsufficientLiquidity();

    modifier onlyManager() {
        if (msg.sender != manager) revert NotManager();
        _;
    }

    constructor(address _usdt, address _manager) {
        if (_usdt == address(0) || _manager == address(0)) revert ZeroAddress();
        USDT = _usdt;
        manager = _manager;
    }

    // manager controls
    function setManager(address _m) external onlyManager {
        if (_m == address(0)) revert ZeroAddress();
        manager = _m;
        emit ManagerUpdated(_m);
    }

    function setAdapter(address adapter, bool allowed) external onlyManager {
        if (adapter == address(0)) revert ZeroAddress();
        if (allowed && !isAdapter[adapter]) {
            adapters.push(adapter);
        }
        isAdapter[adapter] = allowed;
        emit AdapterSet(adapter, allowed);
    }

    function setReserveBps(uint256 bps) external onlyManager {
        require(bps <= 2_000, "max 20%"); // guardrail 
        reserveBps = bps;
        emit ReserveBpsUpdated(bps);
    }

    // view functions 
    function adaptersLength() external view returns (uint256) {
        return adapters.length;
    }

    function totalAssets() public view returns (uint256 tvl) {
        tvl = IERC20(USDT).balanceOf(address(this)); // idle 
        for (uint256 i = 0; i < adapters.length; i++) {
            address ad = adapters[i];
            if (isAdapter[ad]) {
                tvl += IAdapter(ad).totalAssets();
            }
        }
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        if (_totalAssets == 0 || totalShares == 0) return assets; // 1:1 bootstrap
        return (assets * totalShares) / _totalAssets;
    }

    function convertToAssets(uint256 _shares) public view returns (uint256) {
        if (totalShares == 0) return 0;
        return (_shares * totalAssets()) / totalShares;
    }

    function idleTarget() public view returns (uint256) {
        return (totalAssets() * reserveBps) / 10_000;
    }

    // user actions 
    function deposit(uint256 assets) external nonReentrant {
        if (assets == 0) revert ZeroAmount();

        uint256 s = convertToShares(assets);
        totalShares += s;
        shares[msg.sender] += s;

        IERC20(USDT).safeTransferFrom(msg.sender, address(this), assets);
        emit Deposit(msg.sender, assets, s);
    }

    /// @notice Burn `sharesToBurn` and receive pro‑rata assets.
    // note that shares toburn are not actual tokens 
    function withdraw(uint256 sharesToBurn) external nonReentrant {
        if (shares[msg.sender] < sharesToBurn) revert InsufficientShares();

        uint256 assets = convertToAssets(sharesToBurn);

        // Try to pay from idle first
        uint256 idle = IERC20(USDT).balanceOf(address(this));
        if (idle < assets) {
            uint256 shortfall = assets - idle;
            _pullFromAdapters(shortfall);
        }

        // burn shares and pay user
        shares[msg.sender] -= sharesToBurn;
        totalShares -= sharesToBurn;
        IERC20(USDT).safeTransfer(msg.sender, assets);
        emit Withdraw(msg.sender, assets, sharesToBurn);

        // Optional: re‑invest excess idle after paying out.
        // _investExcess();
    }

    // manager functions 
    function pushToAdapter(address adapter, uint256 amount)
        external
        onlyManager
        nonReentrant
    {
        if (!isAdapter[adapter]) revert InvalidAdapter();
        if (amount == 0) revert ZeroAmount();

        // Respect reserve: do not go below idle target
        uint256 idle = IERC20(USDT).balanceOf(address(this));
        uint256 _idleTarget = idleTarget();
        if (idle <= _idleTarget || idle - _idleTarget < amount) revert KeepReserve();

        IERC20(USDT).safeIncreaseAllowance(adapter, amount);
        IAdapter(adapter).deposit(USDT, amount);

        // Reset allowance to 0 for non‑standard tokens (defensive)
        uint256 curr = IERC20(USDT).allowance(address(this), adapter);
        if (curr > 0) IERC20(USDT).safeDecreaseAllowance(adapter, curr);

        emit Invested(adapter, amount);
    }

    function pullFromAdapter(address adapter, uint256 amount)
        external
        onlyManager
        nonReentrant
    {
        if (!isAdapter[adapter]) revert InvalidAdapter();
        if (amount == 0) revert ZeroAmount();

        uint256 beforeBal = IERC20(USDT).balanceOf(address(this));
        IAdapter(adapter).withdraw(USDT, amount, address(this));
        uint256 received = IERC20(USDT).balanceOf(address(this)) - beforeBal;
        require(received > 0, "no funds received"); // optional assertion

        emit Divested(adapter, amount);
    }

    // Internal pull for on‑demand withdrawals 
    function _pullFromAdapters(uint256 shortfall) internal {
        uint256 remaining = shortfall;
        for (uint256 i = 0; i < adapters.length && remaining > 0; i++) {
            address adapter = adapters[i];
            if (!isAdapter[adapter]) continue;

            uint256 aBal = IAdapter(adapter).totalAssets();
            if (aBal == 0) continue;

            uint256 toPull = aBal >= remaining ? remaining : aBal;

            uint256 before = IERC20(USDT).balanceOf(address(this));
            IAdapter(adapter).withdraw(USDT, toPull, address(this));
            uint256 received = IERC20(USDT).balanceOf(address(this)) - before;

            if (received >= remaining) {
                remaining = 0;
            } else {
                remaining -= received;
            }
        }

        if (remaining > 0) revert InsufficientLiquidity();
    }

}
