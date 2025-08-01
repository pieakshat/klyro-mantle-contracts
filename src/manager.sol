//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import {IVault} from "./interfaces/IVault.sol"; // or paste the minimal interface shown above
import {IAdapter} from "./interfaces/IAdapter.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {USDTVault} from "./vault.sol";

contract VaultManager is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    USDTVault public vault;
    address public immutable USDT;

    event VaultSet(address indexed vault);
    event ManagerAction(string action, address indexed adapter, uint256 amount);
    event AdapterSet(address indexed token, address indexed adapter);

    constructor(address _usdt, address initialOwner) Ownable(initialOwner) {
        USDT = _usdt;
    }

    /// @dev keeper can run invest/topUp/rebalance; owner can update config
    address public keeper; 

    mapping(address => IAdapter) public tokenAdapters; 

    error NotKeeper();
    error NotOwner();
    error ZeroAddress();
    error ZeroAmount();
    error AdapterNotSet();

    modifier onlyKeeper() {
        if (msg.sender != keeper && msg.sender != owner()) revert NotKeeper();
        _;
    }

    // Owner functions
    function setVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert ZeroAddress();
        vault = USDTVault(_vault);
        emit VaultSet(_vault);
    }

    function setKeeper(address _keeper) external onlyOwner {
        if (_keeper == address(0)) revert ZeroAddress();
        keeper = _keeper;
    }

    function setAdapter(address token, address adapter) external onlyOwner {
        if (token == address(0) || adapter == address(0)) revert ZeroAddress();
        tokenAdapters[token] = IAdapter(adapter);
        emit AdapterSet(token, adapter);
    }

    function setVaultAdapter(address adapter, bool allowed) external onlyOwner {
        if (adapter == address(0)) revert ZeroAddress();
        vault.setAdapter(adapter, allowed);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Keeper functions
    function depositToAdapter(address token, uint256 amount) external onlyKeeper whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (address(tokenAdapters[token]) == address(0)) revert AdapterNotSet();

        // Push tokens to adapter
        vault.pushToAdapter(address(tokenAdapters[token]), amount);
        
        emit ManagerAction("deposit", address(tokenAdapters[token]), amount);
    }

    function withdrawFromAdapter(address token, uint256 amount) external onlyKeeper whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        if (address(tokenAdapters[token]) == address(0)) revert AdapterNotSet();

        // Pull tokens from adapter
        vault.pullFromAdapter(address(tokenAdapters[token]), amount);
        
        emit ManagerAction("withdraw", address(tokenAdapters[token]), amount);
    }

    // View functions
    function getAdapter(address token) external view returns (address) {
        return address(tokenAdapters[token]);
    }

    function hasAdapter(address token) external view returns (bool) {
        return address(tokenAdapters[token]) != address(0);
    }
}