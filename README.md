# PZZL Contracts

This folder contains the PZZL ERC-20 token and the PZZL bridge custody contract.

## Contracts

- `PZZLToken.sol` mints a fixed initial supply of `10,000,000,000 PZZL` to the deployer. The token is fully immutable: there is no owner, no minting after deployment, and no bridge-coupling logic. Bridging is handled entirely by the separate `PZZLBridge` contract through the standard `approve` / `transferFrom` flow.
- `PZZLBridge.sol` holds PZZL deposits and lets approved operators withdraw only the configured PZZL token to users.

## Bridge Operations

1. Deploy `PZZLToken`.
2. Deploy `PZZLBridge` with the PZZL token address.
3. Add backend signer/operator accounts with `PZZLBridge.setOperator(operator, true)`.

Users deposit into the bridge with a standard two-step approve/deposit flow:

```solidity
PZZLToken.approve(bridgeAddress, amount);
PZZLBridge.deposit(amount, destChainId);
```

This emits `TokenDeposit(account, amount, destChainId)`, which the backend/relayer listens for to release the equivalent amount on the destination chain.

Operator withdrawals use:

```solidity
withdrawToken(receiverAddress, amount, requestId)
```

`requestId` must be unique and non-zero. Reusing it reverts, which protects against accidental duplicate processing.

## Admin Controls

- `setOperator(operator, allowed)` — grants or revokes withdrawal rights for an address.
- `setPZZLTokenContract(newPZZLTokenContract)` — repoints the bridge to a different token address.
- `pause()` / `unpause()` — halts or resumes `deposit` and `withdrawToken`.
- `transferOwnership(newOwner)` / `acceptOwnership()` — two-step ownership transfer.

All admin functions are `onlyOwner`. Consider transferring ownership to a multisig rather than keeping a single EOA as owner.

## Rescue

The owner can rescue non-PZZL ERC-20 tokens sent to the bridge by mistake:

```solidity
rescueToken(tokenContract, receiverAddress, amount)
```

`rescueToken` intentionally reverts (`CannotRescuePZZL`) for the configured PZZL token — deposited/owed PZZL can never be swept out through this function.

## Tests

Install dependencies and run the compile/API tests:

```bash
npm install
npm test
```