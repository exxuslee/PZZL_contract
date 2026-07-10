// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PZZLBridgeHistory
/// @notice Base contract holding the on-chain log of deposits and
///         withdrawals, indexed per-account, so a client can find out
///         "what's been credited to me" via a view method, instead of
///         scanning past events.
/// @dev This is an `abstract contract`, not a standalone deployable
///      contract — it exists purely to keep history-related state, events,
///      and view methods in their own file. The final `PZZLBridge` contract
///      inherits from this directly (one deployed contract, one storage
///      layout). `_recordDeposit` / `_recordWithdraw` are `internal`, so
///      only code inside PZZLBridge itself (i.e. its own deposit/withdraw
///      functions) can ever write a record — no separate access-control
///      check or "which contract is allowed to write" wiring is needed.
///
///      Deposits and withdrawals are stored ONLY per-account (no global
///      flat array, no global counter) — each write costs a single push,
///      and the returned index doubles as the position both in storage and
///      in the corresponding TokenDeposit/TokenWithdraw event, so a client
///      can pinpoint the exact transaction hash for any record without
///      guessing at ordering.
abstract contract PZZLBridgeHistory {
    struct DepositRecord {
        address account;
        uint256 amount;
        uint256 timestamp;
    }

    struct WithdrawRecord {
        bytes32 requestId;
        address account;
        uint256 amount;
        uint256 timestamp;
    }

    mapping(address => DepositRecord[]) private depositsByAccount;
    mapping(address => WithdrawRecord[]) private withdrawalsByAccount;

    // ───────────── Writes (internal — only callable from PZZLBridge itself) ─────────────

    /// @return accountIndex Position of the new record in depositsByAccount[account] —
    ///         same value should be emitted as `indexed index` in TokenDeposit.
    function _recordDeposit(address account, uint256 amount) internal returns (uint256 accountIndex) {
        accountIndex = depositsByAccount[account].length;
        depositsByAccount[account].push(
            DepositRecord({account: account, amount: amount, timestamp: block.timestamp})
        );
    }

    /// @return accountIndex Position of the new record in withdrawalsByAccount[account] —
    ///         same value should be emitted as `indexed index` in TokenWithdraw.
    function _recordWithdraw(
        bytes32 requestId,
        address account,
        uint256 amount
    ) internal returns (uint256 accountIndex) {
        accountIndex = withdrawalsByAccount[account].length;
        withdrawalsByAccount[account].push(
            WithdrawRecord({
                requestId: requestId,
                account: account,
                amount: amount,
                timestamp: block.timestamp
            })
        );
    }

    // ───────────── Public read methods ─────────────

    /// @notice How many deposits a given account has made.
    function depositsCountOf(address account) external view returns (uint256) {
        return depositsByAccount[account].length;
    }

    /// @notice How many withdrawals a given account has received.
    function withdrawalsCountOf(address account) external view returns (uint256) {
        return withdrawalsByAccount[account].length;
    }

    /// @notice Paginated deposit history for `account` — safer against gas limits
    ///         than returning the whole array if an account has a very long history.
    function getDepositsOfPaged(
        address account,
        uint256 offset,
        uint256 limit
    ) external view returns (DepositRecord[] memory result) {
        DepositRecord[] storage list = depositsByAccount[account];
        if (offset >= list.length) {
            return new DepositRecord[](0);
        }
        uint256 end = offset + limit;
        if (end > list.length) {
            end = list.length;
        }
        result = new DepositRecord[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = list[i];
        }
    }

    /// @notice Paginated withdrawal history for `account`.
    function getWithdrawalsOfPaged(
        address account,
        uint256 offset,
        uint256 limit
    ) external view returns (WithdrawRecord[] memory result) {
        WithdrawRecord[] storage list = withdrawalsByAccount[account];
        if (offset >= list.length) {
            return new WithdrawRecord[](0);
        }
        uint256 end = offset + limit;
        if (end > list.length) {
            end = list.length;
        }
        result = new WithdrawRecord[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = list[i];
        }
    }
}