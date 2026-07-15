// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IERC20Permit is IERC20 {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
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
