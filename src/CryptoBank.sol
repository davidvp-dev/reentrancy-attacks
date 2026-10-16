// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

contract CryptoBank {
    mapping(address => uint256) public userBalance;

    function depositEther() external payable {
        require(msg.value >= 1 ether, "Minimum deposit is 1 ETH");
        userBalance[msg.sender] += msg.value;
    }

    function withdrawEther() external {
        uint256 balanceWithdrawn = userBalance[msg.sender];
        require(balanceWithdrawn >= 1 ether, "Not enough balance");

        (bool success,) = msg.sender.call{value: balanceWithdrawn}("");
        require(success, "Transfer failed");

        userBalance[msg.sender] == 0;
    }
}
