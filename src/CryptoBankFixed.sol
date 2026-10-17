// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

contract CryptoBankFixed {
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
     * @notice Withdraws the caller's full balance using CEI pattern
     */
    function withdrawEther() external {
        uint256 balanceWithdrawn = userBalance[msg.sender];
        require(balanceWithdrawn >= 1 ether, "Not enough balance");

        userBalance[msg.sender] = 0;

        (bool success,) = msg.sender.call{value: balanceWithdrawn}("");
        require(success, "Transfer failed");
    }
}
