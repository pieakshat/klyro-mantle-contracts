//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IInitCore} from "./interfaces/IInitCore.sol";
import {IAdapter} from "./interfaces/IAdapter.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";


contract InitProtocolAdapter is IAdapter, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant WAD = 1e18; 
    uint256 private constant SECONDS_PER_YEAR = 365 days; 

    address public vault; 
    IInitCore public initCore;
    ILendingPool public lendingPool; // Lending pool (also the intoken ERC20)
    IERC20 public asset; // usdt is the asset in this case 

    error NotVault(); 
    error AssetMismatch();
    error ZeroAmount(); 


    modifier onlyVault() {
        if (msg.sender != vault) revert NotVault();
        _;
    }

    constructor(address _vault, address _initCore, address _lendingPool) {
        require(_vault != address(0) && _initCore != address(0) && _lendingPool != address(0), "zero addr");
        vault = _vault;
        initCore = IInitCore(_initCore);
        lendingPool  = ILendingPool(_lendingPool);
        asset = IERC20(lendingPool.underlyingToken());
    }

    /// @dev Deposit the underlying into INIT and mint inTokens to this adapter. supposed to be called by the vault contract 
    function deposit(address _asset, uint256 amount) external nonReentrant onlyVault returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount(); 
        if (_asset != address(asset)) revert AssetMismatch();

        // pull the asset from the vault using the approved amount
        IERC20(_asset).safeTransferFrom(vault, address(this), amount); 

        // transfer the tokens to the lending pool 
        IERC20(_asset).safeTransfer(address(lendingPool), amount); 

        // mint inTokens to this adapter
        uint256 mintedShares = initCore.mintTo(address(lendingPool), address(this)); 

        return mintedShares; 
    }

    /// @dev Withdraw 'amount' of underlying to 'to'
    /// Burns adapter's inTokens and sends undeerlying to the vault 
    function withdraw(address _asset, uint256 amount, address to) external nonReentrant onlyVault returns (uint256 received) {
        if (amount == 0) revert ZeroAmount(); 
        if (_asset != address(asset)) revert AssetMismatch(); 

        // Determine how many intoken shares must be burned (with interest accured)
        uint256 sharesNeeded = lendingPool.toSharesCurrent(amount); 

        // adapter's inToken balance is simply ERC20 balance of the pool token 
        uint256 inTokenBalance = IERC20(address(lendingPool)).balanceOf(address(this)); 

        if (sharesNeeded > inTokenBalance) {
            sharesNeeded = inTokenBalance; 
        }

        // transfer inTokens to the pool 
        IERC20(address(lendingPool)).safeTransfer(address(lendingPool), sharesNeeded); 

        received = initCore.burnTo(address(lendingPool), to);
    }

    /// @dev Value of adapter's position in underlying units (view only, no accrual).
    function totalAssets() public view returns (uint256) {
        uint256 inTokenBal = IERC20(address(lendingPool)).balanceOf(address(this));
        if (inTokenBal == 0) return 0;
        // Use stored conversion (view).
        //may be slightly understated until accrue.
        return lendingPool.toAmt(inTokenBal);
    }

    /// @dev INIT has no generic reward stream here; implement if you farm points/tokens via hooks.
    function harvest() external returns (uint256 gained) {
        // No-op by default. If INIT later adds claimables, do it here and return `gained`.
        return 0;
    }

    // rate helpers 

    // @notice Spot supply APR in basis points, derived from per-second rate (1e18 scaled). 
    function supplyAprBps() public view returns (uint256) {
        uint256 rPerSec_e18 = lendingPool.getSupplyRate_e18(); // per-second, 1e18 
        // APR_bps = r_sec * seconds_per_year * 10_000 / 1e18 
        return (rPerSec_e18 * SECONDS_PER_YEAR * 10_000) / WAD; 
    }

    /// @notice Spot borrower APR in basis points 
    function borrowAprBps() public view returns(uint256) {
        uint256 rPerSec_e18 = lendingPool.getBorrowRate_e18(); 
        return (rPerSec_e18 * SECONDS_PER_YEAR * 10_000) / WAD;
    }

    /// @notice Supply APY in basis points, compounded per second.
    /// @dev Computes (1 + r_sec)^(seconds_per_year) - 1 using fixed-point pow.
    function supplyApyBps() public view returns (uint256) {
        uint256 rPerSec_e18 = lendingPool.getSupplyRate_e18();
        if (rPerSec_e18 == 0) return 0;
        uint256 onePlus = WAD + rPerSec_e18;               // 1e18 + r_sec
        uint256 apyWad = _powWad(onePlus, SECONDS_PER_YEAR) - WAD; // WAD-scaled
        return (apyWad * 10_000) / WAD;                    // to bps
    }

    /// @notice Borrower APY in basis points (compounded per second).
    function borrowApyBps() public view returns (uint256) {
        uint256 rPerSec_e18 = lendingPool.getBorrowRate_e18();
        if (rPerSec_e18 == 0) return 0;
        uint256 onePlus = WAD + rPerSec_e18;
        uint256 apyWad = _powWad(onePlus, SECONDS_PER_YEAR) - WAD;
        return (apyWad * 10_000) / WAD;
    }


        /// @dev Fixed-point multiply: (a * b) / 1e18, rounds down.
    function _mulWad(uint256 a, uint256 b) private pure returns (uint256) {
        return (a * b) / WAD;
    }

    /// @dev Exponentiation by squaring in WAD space: baseWad^exp (exp = seconds, up to ~3e7).
    ///      Safe here because baseWad ~= 1e18 + small r, so intermediate products stay << 2^256.
    function _powWad(uint256 baseWad, uint256 exp) private pure returns (uint256 result) {
        result = WAD; // identity
        uint256 b = baseWad;
        uint256 e = exp;
        while (e > 0) {
            if (e & 1 != 0) {
                result = _mulWad(result, b);
            }
            e >>= 1;
            if (e > 0) {
                b = _mulWad(b, b);
            }
        }
    }

}