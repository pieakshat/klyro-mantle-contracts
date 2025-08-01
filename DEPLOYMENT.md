# Deployment Guide

## Prerequisites

1. **Foundry Setup**: Make sure you have Foundry installed
2. **Environment Variables**: Set up your `.env` file with the required addresses
3. **Network Configuration**: Ensure you're connected to the correct network

## Environment Variables

Create a `.env` file with the following variables:

```bash
# Deployment Configuration
DEPLOYER=0x0000000000000000000000000000000000000000
OWNER=0x0000000000000000000000000000000000000000
KEEPER=0x0000000000000000000000000000000000000000
USDT=0x0000000000000000000000000000000000000000
INIT_CORE=0x0000000000000000000000000000000000000000
LENDING_POOL=0x0000000000000000000000000000000000000000
PRIVATE_KEY=0x0000000000000000000000000000000000000000000000000000000000000000
```

### Address Descriptions

- **DEPLOYER**: The account that will deploy the contracts
- **OWNER**: Will have admin rights on VaultManager (can set vault, keeper, adapters)
- **KEEPER**: Can perform deposit/withdraw operations through the manager
- **USDT**: The USDT token address on your target network
- **INIT_CORE**: The Init Protocol's InitCore contract address
- **LENDING_POOL**: The Init Protocol's lending pool address for USDT

## Deployment Steps

### 1. Set Environment Variables

```bash
# Copy the example and fill in your addresses
cp .env.example .env
# Edit .env with your actual addresses
```

### 2. Deploy Contracts

```bash
# Deploy to local network for testing
forge script script/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url $TESTNET_RPC --broadcast --verify

# Deploy to mainnet
forge script script/Deploy.s.sol --rpc-url $MAINNET_RPC --broadcast --verify
```

### 3. Verify Deployment

After deployment, the script will output all contract addresses and verify the configuration.

## Deployment Order

The script deploys contracts in this order:

1. **VaultManager** - The main management contract
2. **USDTVault** - The vault contract with manager as initial manager
3. **InitProtocolAdapter** - The adapter for Init Protocol
4. **Configuration** - Sets up all the connections between contracts

## Post-Deployment Verification

Run the verification function to ensure everything is configured correctly:

```bash
# Call the verification function
cast call <VAULT_ADDRESS> "manager()" --rpc-url $RPC_URL
cast call <MANAGER_ADDRESS> "vault()" --rpc-url $RPC_URL
cast call <ADAPTER_ADDRESS> "vault()" --rpc-url $RPC_URL
```

## Usage

### For Users

1. **Deposit**: Users can deposit USDT directly to the vault
2. **Withdraw**: Users can withdraw their shares from the vault

### For Keeper

1. **Deposit to Adapter**: `manager.depositToAdapter(USDT_ADDRESS, amount)`
2. **Withdraw from Adapter**: `manager.withdrawFromAdapter(USDT_ADDRESS, amount)`

### For Owner

1. **Set Keeper**: `manager.setKeeper(newKeeper)`
2. **Pause/Unpause**: `manager.pause()` / `manager.unpause()`
3. **Add Adapters**: `manager.setAdapter(token, adapter)`

## Security Considerations

1. **Owner**: Should be a multisig or DAO
2. **Keeper**: Should be a trusted account or automated system
3. **Pause**: Use in emergencies to stop all operations
4. **Timelock**: Consider adding timelock for admin functions

## Testing

Before mainnet deployment, test thoroughly:

```bash
# Run all tests
forge test

# Run specific test suites
forge test --match-contract VaultTest
forge test --match-contract InitAdapterVaultTest
forge test --match-contract ManagerTest
``` 