// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

/**
 * @title CryptoBank
 * @notice Intentionally vulnerable ETH vault used as the victim in the reentrancy POC.
 * @dev DO NOT USE IN PRODUCTION. `withdrawEther` performs the external call before
 *      updating state (violates Checks-Effects-Interactions) and has no reentrancy guard.
 */
contract CryptoBank {
    /// @notice ETH balance credited to each depositor.
    mapping(address => uint256) public userBalance;

    /**
     * @notice Deposits ETH into the bank, crediting it to the caller's balance.
     * @dev Reverts if `msg.value` is lower than 1 ETH.
     */
    function depositEther() external payable {
        require(msg.value >= 1 ether, "Minimum deposit is 1 ETH");
        userBalance[msg.sender] += msg.value;
    }

    /**
     * @notice Withdraws the caller's full balance.
     * @dev VULNERABLE: ETH is sent via a low-level call before the balance is reset,
     *      so a malicious `receive()` can re-enter this function and drain the bank.
     *      Reverts if the caller's balance is lower than 1 ETH or if the ETH transfer fails.
     */
    function withdrawEther() external {
        uint256 balanceWithdrawn = userBalance[msg.sender];
        require(balanceWithdrawn >= 1 ether, "Not enough balance");

        (bool success,) = msg.sender.call{value: balanceWithdrawn}("");
        require(success, "Transfer failed");

        userBalance[msg.sender] = 0;
    }
}
