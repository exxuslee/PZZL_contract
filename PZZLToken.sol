// SPDX-License-Identifier: MIT
//
pragma solidity ^0.8.20;

import {IERC20, IERC20Permit} from "./PZZLBridgeCommon.sol";

/// @title PZZLToken
/// @notice ERC-20 token with EIP-2612 permit support, fixed initial supply of 10 billion PZZL.
contract PZZLToken is IERC20, IERC20Permit {
    string public constant name = "PZZL";
    string public constant symbol = "PZZL";
    uint8 public constant decimals = 18;

    uint256 public constant INITIAL_SUPPLY = 10_000_000_000 * 10 ** uint256(decimals);

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public nonces;

    bytes32 public constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    // secp256k1 curve order / 2 - upper bound for valid `s` (EIP-2 / malleability guard)
    uint256 private constant _SECP256K1N_DIV_2 =
    0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    bytes32 private immutable _CACHED_DOMAIN_SEPARATOR;
    uint256 private immutable _CACHED_CHAIN_ID;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error TransferToZeroAddress();
    error ApproveToZeroAddress();
    error InsufficientBalance();
    error InsufficientAllowance();
    error AllowanceBelowZero();
    error PermitExpired();
    error InvalidSignature();

    constructor() {
        totalSupply = INITIAL_SUPPLY;
        balanceOf[msg.sender] = INITIAL_SUPPLY;

        _CACHED_CHAIN_ID = block.chainid;
        _CACHED_DOMAIN_SEPARATOR = _buildDomainSeparator();

        emit Transfer(address(0), msg.sender, INITIAL_SUPPLY);
    }

    //  ERC-20 core

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

    //  Allowance helpers

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

    //  EIP-2612 permit

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == _CACHED_CHAIN_ID ? _CACHED_DOMAIN_SEPARATOR : _buildDomainSeparator();
    }

    /// @notice Sets `allowance[owner][spender] = value` via an off-chain signature,
    ///         avoiding a separate on-chain approve transaction.
    function permit(
        address tokenOwner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp > deadline) revert PermitExpired();

        // EIP-2 malleability guard: reject the "upper" s and any v other than 27/28.
        if (uint256(s) > _SECP256K1N_DIV_2) revert InvalidSignature();
        if (v != 27 && v != 28) revert InvalidSignature();

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, tokenOwner, spender, value, nonces[tokenOwner]++, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));

        address recovered = ecrecover(digest, v, r, s);
        if (recovered == address(0) || recovered != tokenOwner) revert InvalidSignature();

        _approve(tokenOwner, spender, value);
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    //  Internal

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
