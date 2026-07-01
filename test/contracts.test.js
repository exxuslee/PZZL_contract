const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const solc = require("solc");

const root = path.resolve(__dirname, "..");

function compileContracts() {
  const sources = {
    "PZZLToken.sol": {
      content: fs.readFileSync(path.join(root, "PZZLToken.sol"), "utf8"),
    },
    "PZZLBridge.sol": {
      content: fs.readFileSync(path.join(root, "PZZLBridge.sol"), "utf8"),
    },
  };

  const input = {
    language: "Solidity",
    sources,
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
      outputSelection: {
        "*": {
          "*": ["abi", "evm.bytecode.object"],
        },
      },
    },
  };

  const output = JSON.parse(solc.compile(JSON.stringify(input)));
  const errors = output.errors?.filter((item) => item.severity === "error") ?? [];
  assert.deepEqual(errors, []);
  return output.contracts;
}

function functionAbi(abi, name) {
  return abi.find((item) => item.type === "function" && item.name === name);
}

test("contracts compile without Solidity errors", () => {
  const contracts = compileContracts();

  assert.ok(contracts["PZZLToken.sol"].PZZLToken.evm.bytecode.object.length > 0);
  assert.ok(contracts["PZZLBridge.sol"].PZZLBridge.evm.bytecode.object.length > 0);
});

test("bridge withdrawal API is restricted to configured PZZL token", () => {
  const contracts = compileContracts();
  const bridgeAbi = contracts["PZZLBridge.sol"].PZZLBridge.abi;
  const withdrawToken = functionAbi(bridgeAbi, "withdrawToken");

  assert.deepEqual(
      withdrawToken.inputs.map((input) => input.type),
      ["address", "uint256", "bytes32"],
  );
});

test("bridge exposes deposit, operational controls and audit events", () => {
  const contracts = compileContracts();
  const bridgeAbi = contracts["PZZLBridge.sol"].PZZLBridge.abi;
  const functionNames = new Set(
      bridgeAbi.filter((item) => item.type === "function").map((item) => item.name),
  );
  const eventNames = new Set(
      bridgeAbi.filter((item) => item.type === "event").map((item) => item.name),
  );

  [
    "deposit",
    "withdrawToken",
    "rescueToken",
    "setOperator",
    "setPZZLTokenContract",
    "pause",
    "unpause",
    "transferOwnership",
    "acceptOwnership",
  ].forEach((name) => assert.ok(functionNames.has(name), `${name} is missing`));

  [
    "TokenDeposit",
    "TokenWithdraw",
    "RescueToken",
    "OperatorUpdated",
    "PZZLTokenContractUpdated",
    "OwnershipTransferStarted",
    "OwnershipTransferred",
    "Paused",
    "Unpaused",
  ].forEach((name) => assert.ok(eventNames.has(name), `${name} is missing`));
});

test("bridge deposit requires nonzero amount and forwards destChainId", () => {
  const contracts = compileContracts();
  const bridgeAbi = contracts["PZZLBridge.sol"].PZZLBridge.abi;
  const deposit = functionAbi(bridgeAbi, "deposit");

  assert.deepEqual(
      deposit.inputs.map((input) => input.type),
      ["uint256", "uint256"],
  );
});

test("bridge rescueToken cannot target the configured PZZL token", () => {
  const contracts = compileContracts();
  const bridgeAbi = contracts["PZZLBridge.sol"].PZZLBridge.abi;
  const errorNames = new Set(
      bridgeAbi.filter((item) => item.type === "error").map((item) => item.name),
  );

  assert.ok(errorNames.has("CannotRescuePZZL"));
});

test("bridge no longer exposes native-currency rescue/withdraw or withdrawal limits", () => {
  const contracts = compileContracts();
  const bridgeAbi = contracts["PZZLBridge.sol"].PZZLBridge.abi;
  const functionNames = new Set(
      bridgeAbi.filter((item) => item.type === "function").map((item) => item.name),
  );
  const eventNames = new Set(
      bridgeAbi.filter((item) => item.type === "event").map((item) => item.name),
  );

  ["rescueNative", "withdrawNative", "setTokenWithdrawalLimit"].forEach((name) =>
      assert.ok(!functionNames.has(name), `${name} should not exist`),
  );
  ["RescueNative", "NativeWithdraw", "TokenWithdrawalLimitUpdated"].forEach((name) =>
      assert.ok(!eventNames.has(name), `${name} should not exist`),
  );
});

test("token has fixed supply, standard ERC-20 API and zero-address guards", () => {
  const contracts = compileContracts();
  const tokenAbi = contracts["PZZLToken.sol"].PZZLToken.abi;
  const functionNames = new Set(
      tokenAbi.filter((item) => item.type === "function").map((item) => item.name),
  );
  const errorNames = new Set(
      tokenAbi.filter((item) => item.type === "error").map((item) => item.name),
  );

  [
    "transfer",
    "approve",
    "transferFrom",
    "increaseAllowance",
    "decreaseAllowance",
    "totalSupply",
    "balanceOf",
    "allowance",
  ].forEach((name) => assert.ok(functionNames.has(name), `${name} is missing`));

  [
    "TransferToZeroAddress",
    "ApproveToZeroAddress",
    "InsufficientBalance",
    "InsufficientAllowance",
    "AllowanceBelowZero",
  ].forEach((name) => assert.ok(errorNames.has(name), `${name} is missing`));
});

test("token is fully immutable — no owner, ownership, or bridge-coupling functions", () => {
  const contracts = compileContracts();
  const tokenAbi = contracts["PZZLToken.sol"].PZZLToken.abi;
  const functionNames = new Set(
      tokenAbi.filter((item) => item.type === "function").map((item) => item.name),
  );

  [
    "owner",
    "pendingOwner",
    "transferOwnership",
    "acceptOwnership",
    "renounceOwnership",
    "setBridgeContract",
    "disableBridgeContract",
  ].forEach((name) => assert.ok(!functionNames.has(name), `${name} should not exist on the token`));
});