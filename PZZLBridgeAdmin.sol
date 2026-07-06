// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PZZLBridgeAdmin
/// @notice Base contract holding all admin/ownership/config state for the
///         PZZL bridge: owner, pending owner, operator whitelist, pause
///         switch, and the address of the PZZL token being bridged.
/// @dev This is an `abstract contract`, not a standalone deployable
///      contract — it exists purely to keep admin-related state, events,
///      errors, and functions in their own file. The final `PZZLBridge`
///      contract inherits from this directly, so there is only ONE
///      deployed contract and ONE storage layout; there are no external
///      calls between "layers" at runtime.
abstract contract PZZLBridgeAdmin {
    address public owner;
    address public pendingOwner;
    address public pzzlTokenContract;
    bool public paused;

    mapping(address => bool) public operators;

    event OperatorUpdated(address indexed operator, bool allowed);
    event PZZLTokenContractUpdated(address indexed previousPZZLTokenContract, address indexed newPZZLTokenContract);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    error NotOwner();
    error NotPendingOwner();
    error NotOperator();
    error ZeroAddress();
    error EnforcedPause();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyOperator() {
        if (!operators[msg.sender]) revert NotOperator();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert EnforcedPause();
        _;
    }

    constructor(address initialPZZLTokenContract) {
        if (initialPZZLTokenContract == address(0)) revert ZeroAddress();

        pzzlTokenContract = initialPZZLTokenContract;
        owner = msg.sender;
        operators[msg.sender] = true;

        emit OwnershipTransferred(address(0), msg.sender);
        emit OperatorUpdated(msg.sender, true);
    }

    function setOperator(address operator, bool allowed) external onlyOwner {
        if (operator == address(0)) revert ZeroAddress();
        operators[operator] = allowed;

        emit OperatorUpdated(operator, allowed);
    }

    function setPZZLTokenContract(address newPZZLTokenContract) external onlyOwner {
        if (newPZZLTokenContract == address(0)) revert ZeroAddress();

        address previousPZZLTokenContract = pzzlTokenContract;
        pzzlTokenContract = newPZZLTokenContract;

        emit PZZLTokenContractUpdated(previousPZZLTokenContract, newPZZLTokenContract);
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused(msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        pendingOwner = newOwner;

        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        if (msg.sender != pendingOwner) revert NotPendingOwner();

        address previousOwner = owner;
        owner = pendingOwner;
        pendingOwner = address(0);

        emit OwnershipTransferred(previousOwner, owner);
    }
}
