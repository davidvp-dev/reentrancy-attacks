// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {ReentrancyAttack} from "../src/ReentrancyAttack.sol";
import {CryptoBank} from "../src/CryptoBank.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract ReentrancyAttackTest is Test {
    ReentrancyAttack reentrancyAttack;
    CryptoBank cryptoBank;
    address deployAttacker = vm.addr(1);
    address randomUser1 = makeAddr("alice");
    address randomUser2 = makeAddr("bob");
    address randomUser3 = makeAddr("charlie");

    function setUp() public {
        vm.deal(deployAttacker, 10 ether);
        vm.deal(randomUser1, 10 ether);
        vm.deal(randomUser2, 10 ether);
        vm.deal(randomUser3, 10 ether);
        cryptoBank = new CryptoBank();

        vm.startPrank(deployAttacker);
        reentrancyAttack = new ReentrancyAttack(address(cryptoBank));
        vm.stopPrank();
    }

    function testDeploysOK() public view {
        assertNotEq(address(reentrancyAttack), address(0));
        assertNotEq(address(cryptoBank), address(0));
    }

    function testAttackOK() public {
        _depositRandomUserFunds();
        vm.startPrank(deployAttacker);
        uint256 attackValue = 1 ether;

        uint256 previousReentrancyAttackBalance = address(reentrancyAttack).balance;
        uint256 previousCryptoBankBalance = address(cryptoBank).balance;
        reentrancyAttack.attack{value: attackValue}();
        uint256 afterReentrancyAttackBalance = address(reentrancyAttack).balance;
        uint256 afterCryptoBankBalance = address(cryptoBank).balance;

        assertEq(afterReentrancyAttackBalance, previousReentrancyAttackBalance + previousCryptoBankBalance + attackValue);
        assertEq(afterCryptoBankBalance, 0);

        vm.stopPrank();
    }

    function testAttackKO_lessThan1Ether() public {
        _depositRandomUserFunds();
        vm.startPrank(deployAttacker);
        uint256 attackValue = 0.1 ether;

        vm.expectRevert("Need at least 1 ETH to attack");
        reentrancyAttack.attack{value: attackValue}();

        vm.stopPrank();
    }

    function _depositRandomUserFunds() internal {
        vm.startPrank(randomUser1);
        cryptoBank.depositEther{value: 1 ether}();
        vm.stopPrank();

        vm.startPrank(randomUser2);
        cryptoBank.depositEther{value: 1 ether}();
        vm.stopPrank();

        vm.startPrank(randomUser3);
        cryptoBank.depositEther{value: 1 ether}();
        vm.stopPrank();

        assertEq(address(cryptoBank).balance, 3 ether);
    }
}
