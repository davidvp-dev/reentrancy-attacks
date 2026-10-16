// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

/**
 * @title ICryptoBank
 * @notice Minimal interface used by the attacker to interact with CryptoBank.
 */
interface ICryptoBank {
    /**
     * @notice Deposits ETH into the bank on behalf of the caller.
     */
    function depositEther() external payable;

    /**
     * @notice Withdraws the caller's full balance from the bank.
     */
    function withdrawEther() external;
}
