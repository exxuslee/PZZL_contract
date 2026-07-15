// SPDX-License-Identifier: MIT
//
pragma solidity ^0.8.26;

import {PZZLBridgeAdmin} from "./PZZLBridgeAdmin.sol";
import {SafeERC20, IERC20, IERC20Permit} from "./PZZLCommon.sol";
import {PZZLBridgeHistory} from "./PZZLBridgeHistory.sol";

/// @title PZZLBridge
/// @notice Holds PZZL deposits (via explicit deposit() + approve/transferFrom) and allows
///         approved operators to withdraw PZZL to users on withdrawal requests.
///         Includes a pause switch and a rescue function for PZZL-unrelated ERC-20 tokens.
contract PZZLBridge is PZZLBridgeAdmin, PZZLBridgeHistory {
    using SafeERC20 for IERC20;

    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    mapping(bytes32 => bool) private processedRequests;

    uint256 private reentrancyStatus;

    event TokenDeposit(uint256 indexed index, address indexed account, uint256 amount);
    event TokenWithdraw(uint256 indexed index, bytes32 indexed requestId, address indexed account, uint256 amount);
    event RescueToken(address indexed tokenContract, address indexed receiver, uint256 amount);

    error ZeroAmount();
    error ZeroRequestId();
    error RequestAlreadyProcessed();
    error CannotRescuePZZL();
    error ReentrantCall();

    modifier nonReentrant() {
        if (reentrancyStatus == ENTERED) revert ReentrantCall();
        reentrancyStatus = ENTERED;
        _;
        reentrancyStatus = NOT_ENTERED;
    }

    constructor(address initialPZZLToken) PZZLBridgeAdmin(initialPZZLToken) {
        reentrancyStatus = NOT_ENTERED;
    }

    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        IERC20(pzzlToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 depositIndex = _recordDeposit(msg.sender, amount);
        emit TokenDeposit(depositIndex, msg.sender, amount);
    }

    function depositWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        IERC20Permit(pzzlToken).permit(msg.sender, address(this), amount, deadline, v, r, s);
        IERC20(pzzlToken).safeTransferFrom(msg.sender, address(this), amount);
        uint256 depositIndex = _recordDeposit(msg.sender, amount);
        emit TokenDeposit(depositIndex, msg.sender, amount);
    }

    function withdraw(
        address receiverAddress,
        uint256 amount,
        bytes32 requestId
    ) external onlyOperator nonReentrant whenNotPaused {
        if (receiverAddress == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _markRequestProcessed(requestId);
        IERC20(pzzlToken).safeTransfer(receiverAddress, amount);
        uint256 withdrawIndex = _recordWithdraw(requestId, receiverAddress, amount);
        emit TokenWithdraw(withdrawIndex, requestId, receiverAddress, amount);
    }

    // Rescue (owner-gated, cannot touch bridge-owed funds)

    /// @notice Rescues ERC-20 tokens mistakenly sent to this contract.
    /// @dev Always blocked for the current pzzlTokenContract - deposited/owed PZZL
    ///      can never be swept out via this function.
    function rescueToken(address tokenContract, address receiverAddress, uint256 amount) external onlyOwner {
        if (tokenContract == address(0) || receiverAddress == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (tokenContract == pzzlToken) revert CannotRescuePZZL();

        IERC20(tokenContract).safeTransfer(receiverAddress, amount);
        emit RescueToken(tokenContract, receiverAddress, amount);
    }

    // Internal

    function _markRequestProcessed(bytes32 requestId) private {
        if (requestId == bytes32(0)) revert ZeroRequestId();
        if (processedRequests[requestId]) revert RequestAlreadyProcessed();
        processedRequests[requestId] = true;
    }
}
