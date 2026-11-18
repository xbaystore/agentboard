// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Test-only stand-in for the SPACE ID Agent ID collection.
///         NOT deployed to mainnet; lets the test suite grant/revoke
///         "Agent ID ownership" by setting balances.
contract MockAgentID {
    mapping(address => uint256) private _balances;

    function setBalance(address owner, uint256 amount) external {
        _balances[owner] = amount;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _balances[owner];
    }
}
