//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20; 

interface IAdapter {
    function deposit(address asset, uint256 amount) external returns (uint256);
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function totalAssets() external view returns (uint256);
    function harvest() external returns (uint256 gained); // optional
}