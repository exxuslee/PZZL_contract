// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

library SafeERC20 {
    error SafeTransferFailed();
    error SafeTransferFromFailed();
    error SafeTransferToNonContract();

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        if (address(token).code.length == 0) revert SafeTransferToNonContract();

        (bool success, bytes memory returndata) =
                                address(token).call(abi.encodeCall(IERC20.transfer, (to, value)));

        if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
            revert SafeTransferFailed();
        }
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        if (address(token).code.length == 0) revert SafeTransferToNonContract();

        (bool success, bytes memory returndata) =
                                address(token).call(abi.encodeCall(IERC20.transferFrom, (from, to, value)));

        if (!success || (returndata.length > 0 && !abi.decode(returndata, (bool)))) {
            revert SafeTransferFromFailed();
        }
    }
}

/// @title PZZLBridge
/// @notice Holds PZZL deposits (via explicit deposit() + approve/transferFrom) and allows
///         approved operators to withdraw PZZL to users on withdrawal requests.
///         Includes a pause switch and rescue functions for both PZZL-unrelated ERC-20
///         tokens and accidentally sent native currency (BNB).
/// @dev PZZL_TOKEN is pointed to by `pzzlTokenContract`, used both for deposits and to
///      block rescue of the bridged token. The contract does not use native currency
///      for anything; any BNB balance can only come from mistaken transfers and is
///      always fully rescuable.
contract PZZLBridge {
    using SafeERC20 for IERC20;

    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    address public pzzlTokenContract;
    address public owner;
    address public pendingOwner;

    bool public paused;

    mapping(address => bool) public operators;
    mapping(bytes32 => bool) public processedRequests;

    uint256 private reentrancyStatus;

    event TokenDeposit(address indexed account, uint256 amount);
    event TokenWithdraw(bytes32 indexed requestId, address indexed account, uint256 amount);
    event RescueToken(address indexed tokenContract, address indexed receiver, uint256 amount);
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
    error ZeroAmount();
    error ZeroRequestId();
    error RequestAlreadyProcessed();
    error CannotRescuePZZL();
    error ReentrantCall();
    error EnforcedPause();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyOperator() {
        if (!operators[msg.sender]) revert NotOperator();
        _;
    }

    modifier nonReentrant() {
        if (reentrancyStatus == ENTERED) revert ReentrantCall();
        reentrancyStatus = ENTERED;
        _;
        reentrancyStatus = NOT_ENTERED;
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
        reentrancyStatus = NOT_ENTERED;

        emit OwnershipTransferred(address(0), msg.sender);
        emit OperatorUpdated(msg.sender, true);
    }

    // ─────────────────────────────────────────
    //  Deposits (user-facing)
    // ─────────────────────────────────────────

    /// @notice Deposits PZZL into the bridge to be released on the destination chain.
    ///         Caller must first call `token.approve(bridge, amount)`.
    /// @param amount Amount of PZZL to deposit.
    function deposit(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();

        IERC20(pzzlTokenContract).safeTransferFrom(msg.sender, address(this), amount);

        emit TokenDeposit(msg.sender, amount);
    }

    // ─────────────────────────────────────────
    //  Withdrawals (operator-gated)
    // ─────────────────────────────────────────

    function withdraw(
        address receiverAddress,
        uint256 amount,
        bytes32 requestId
    ) external onlyOperator nonReentrant whenNotPaused {
        if (receiverAddress == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        _markRequestProcessed(requestId);

        IERC20(pzzlTokenContract).safeTransfer(receiverAddress, amount);

        emit TokenWithdraw(requestId, receiverAddress, amount);
    }

    // ─────────────────────────────────────────
    //  Rescue (owner-gated, cannot touch bridge-owed funds)
    // ─────────────────────────────────────────

    /// @notice Rescues ERC-20 tokens mistakenly sent to this contract.
    /// @dev Always blocked for the current pzzlTokenContract — deposited/owed PZZL
    ///      can never be swept out via this function.
    function rescueToken(address tokenContract, address receiverAddress, uint256 amount) external onlyOwner nonReentrant {
        if (tokenContract == address(0) || receiverAddress == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (tokenContract == pzzlTokenContract) revert CannotRescuePZZL();

        IERC20(tokenContract).safeTransfer(receiverAddress, amount);

        emit RescueToken(tokenContract, receiverAddress, amount);
    }

    // ─────────────────────────────────────────
    //  Admin
    // ─────────────────────────────────────────

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

    // ─────────────────────────────────────────
    //  Internal
    // ─────────────────────────────────────────

    function _markRequestProcessed(bytes32 requestId) private {
        if (requestId == bytes32(0)) revert ZeroRequestId();
        if (processedRequests[requestId]) revert RequestAlreadyProcessed();
        processedRequests[requestId] = true;
    }
}