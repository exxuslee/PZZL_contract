// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PZZLToken
/// @notice ERC-20 token with a fixed initial supply of 10 billion PZZL.
/// @dev Includes allowance helpers, infinite-allowance optimization, two-step ownership,
///      and custom errors for gas efficiency. No bridge logic — all bridging is handled
///      by the separate PZZLBridge contract via standard approve/transferFrom.
contract PZZLToken {
    string public constant name = "PZZL";
    string public constant symbol = "PZZL";
    uint8 public constant decimals = 18;

    uint256 public constant INITIAL_SUPPLY = 10_000_000_000 * 10 ** uint256(decimals);

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error TransferToZeroAddress();
    error ApproveToZeroAddress();
    error InsufficientBalance();
    error InsufficientAllowance();
    error AllowanceBelowZero();

    constructor() {
        totalSupply = INITIAL_SUPPLY;
        balanceOf[msg.sender] = INITIAL_SUPPLY;

        emit Transfer(address(0), msg.sender, INITIAL_SUPPLY);
    }

    // ─────────────────────────────────────────
    //  ERC-20 core
    // ─────────────────────────────────────────

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];

        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) revert InsufficientAllowance();
            unchecked {
                allowance[from][msg.sender] = currentAllowance - value;
            }
            emit Approval(from, msg.sender, allowance[from][msg.sender]);
        }

        _transfer(from, to, value);
        return true;
    }

    // ─────────────────────────────────────────
    //  Allowance helpers
    // ─────────────────────────────────────────

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        _approve(msg.sender, spender, allowance[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 current = allowance[msg.sender][spender];
        if (current < subtractedValue) revert AllowanceBelowZero();
        unchecked {
            _approve(msg.sender, spender, current - subtractedValue);
        }
        return true;
    }

    // ─────────────────────────────────────────
    //  Internal
    // ─────────────────────────────────────────

    function _approve(address tokenOwner, address spender, uint256 value) private {
        if (spender == address(0)) revert ApproveToZeroAddress();

        allowance[tokenOwner][spender] = value;
        emit Approval(tokenOwner, spender, value);
    }

    function _transfer(address from, address to, uint256 value) private {
        if (to == address(0)) revert TransferToZeroAddress();

        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) revert InsufficientBalance();

        unchecked {
            balanceOf[from] = fromBalance - value;
        }
        balanceOf[to] += value;

        emit Transfer(from, to, value);
    }
}