// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {ReentrancyAttack} from "../src/ReentrancyAttack.sol";
import {CryptoBank} from "../src/CryptoBank.sol";
import {CryptoBankFixed} from "../src/CryptoBankFixed.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title ReentrancyAttackTest
 * @notice Test suite for the CryptoBank reentrancy POC.
 */
contract ReentrancyAttackTest is Test {
    ReentrancyAttack reentrancyAttack;
    CryptoBank cryptoBank;
    CryptoBankFixed cryptoBankFixed;
    ReentrancyAttack reentrancyAttackFixed;
    address deployAttacker = vm.addr(1);
    address randomUser1 = makeAddr("alice");
    address randomUser2 = makeAddr("bob");
    address randomUser3 = makeAddr("charlie");

    /**
     * @notice Funds the actors and deploys the bank and the attacker contract.
     */
    function setUp() public {
        vm.deal(deployAttacker, 10 ether);
        vm.deal(randomUser1, 10 ether);
        vm.deal(randomUser2, 10 ether);
        vm.deal(randomUser3, 10 ether);
        cryptoBank = new CryptoBank();
        cryptoBankFixed = new CryptoBankFixed();

        vm.startPrank(deployAttacker);
        reentrancyAttack = new ReentrancyAttack(address(cryptoBank));
        reentrancyAttackFixed = new ReentrancyAttack(address(cryptoBankFixed));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                               DEPLOYMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Both contracts are deployed and the attacker is correctly configured.
     */
    function testDeploysOK() public view {
        assertNotEq(address(reentrancyAttack), address(0));
        assertNotEq(address(cryptoBank), address(0));
        assertNotEq(address(cryptoBankFixed), address(0));
        assertNotEq(address(reentrancyAttackFixed), address(0));
        assertEq(reentrancyAttack.cryptoBankAddress(), address(cryptoBank));
        assertEq(reentrancyAttack.owner(), deployAttacker);
        assertEq(reentrancyAttackFixed.cryptoBankAddress(), address(cryptoBankFixed));
        assertEq(reentrancyAttackFixed.owner(), deployAttacker);
    }

    /*//////////////////////////////////////////////////////////////
                         CRYPTOBANK (HAPPY / KO)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice A deposit of at least 1 ETH is credited to the depositor.
     */
    function testDepositOK() public {
        vm.prank(randomUser1);
        cryptoBank.depositEther{value: 2 ether}();

        assertEq(cryptoBank.userBalance(randomUser1), 2 ether);
        assertEq(address(cryptoBank).balance, 2 ether);
    }

    /**
     * @notice Deposits below 1 ETH revert.
     */
    function testDepositKO_lessThan1Ether() public {
        vm.prank(randomUser1);
        vm.expectRevert("Minimum deposit is 1 ETH");
        cryptoBank.depositEther{value: 0.5 ether}();
    }

    /**
     * @notice An honest user can withdraw what they deposited.
     */
    function testWithdrawOK() public {
        vm.startPrank(randomUser1);
        cryptoBank.depositEther{value: 1 ether}();
        uint256 balanceBefore = randomUser1.balance;
        cryptoBank.withdrawEther();
        vm.stopPrank();

        assertEq(randomUser1.balance, balanceBefore + 1 ether);
        assertEq(address(cryptoBank).balance, 0);
    }

    /**
     * @notice Withdrawing without a balance of at least 1 ETH reverts.
     */
    function testWithdrawKO_notEnoughBalance() public {
        vm.prank(randomUser1);
        vm.expectRevert("Not enough balance");
        cryptoBank.withdrawEther();
    }

    /**
     * @notice Withdrawal reverts when the receiver cannot accept ETH.
     * @dev This test contract has no `receive`/`fallback`, so the low-level call fails.
     */
    function testWithdrawKO_transferFailed() public {
        vm.deal(address(this), 1 ether);
        cryptoBank.depositEther{value: 1 ether}();

        vm.expectRevert("Transfer failed");
        cryptoBank.withdrawEther();
    }

    /*//////////////////////////////////////////////////////////////
                                ATTACK
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The attacker drains every wei of the bank via reentrancy.
     */
    function testAttackOK() public {
        _depositRandomUserFunds();
        vm.startPrank(deployAttacker);
        uint256 attackValue = 1 ether;

        uint256 previousReentrancyAttackBalance = address(reentrancyAttack).balance;
        uint256 previousCryptoBankBalance = address(cryptoBank).balance;
        reentrancyAttack.attack{value: attackValue}();
        uint256 afterReentrancyAttackBalance = address(reentrancyAttack).balance;
        uint256 afterCryptoBankBalance = address(cryptoBank).balance;

        assertEq(
            afterReentrancyAttackBalance, previousReentrancyAttackBalance + previousCryptoBankBalance + attackValue
        );
        assertEq(afterCryptoBankBalance, 0);

        vm.stopPrank();
    }

    /**
     * @notice After the attack, honest users can no longer withdraw: the bank is insolvent.
     */
    function testAttackOK_victimsCannotWithdraw() public {
        _depositRandomUserFunds();
        vm.prank(deployAttacker);
        reentrancyAttack.attack{value: 1 ether}();

        // Accounting still says alice has 1 ETH, but the bank holds 0.
        assertEq(cryptoBank.userBalance(randomUser1), 1 ether);
        vm.prank(randomUser1);
        vm.expectRevert("Transfer failed");
        cryptoBank.withdrawEther();
    }

    /**
     * @notice Attacks with less than 1 ETH revert.
     */
    function testAttackKO_lessThan1Ether() public {
        _depositRandomUserFunds();
        vm.startPrank(deployAttacker);
        uint256 attackValue = 0.1 ether;

        vm.expectRevert("Need at least 1 ETH to attack");
        reentrancyAttack.attack{value: attackValue}();

        vm.stopPrank();
    }

    /**
     * @notice The attack fails atomically if the bank's remaining balance is not a multiple
     *         of the attacker's deposit: the last nested call fails and the whole tx reverts.
     * @dev 3 ETH in the bank + 2 ETH deposit = 5 ETH -> 3 -> 1 ETH left, which is >= 1 ETH,
     *      so `receive` re-enters asking for 2 ETH and the transfer fails.
     */
    function testAttackKO_bankBalanceNotMultipleOfDeposit() public {
        _depositRandomUserFunds();
        vm.prank(deployAttacker);
        vm.expectRevert("Transfer failed");
        reentrancyAttack.attack{value: 2 ether}();

        assertEq(address(cryptoBank).balance, 3 ether);
    }

    /**
     * @notice If the bank is empty, the attack only gets back the attacker's own deposit.
     */
    function testAttackOK_emptyBank() public {
        vm.prank(deployAttacker);
        reentrancyAttack.attack{value: 1 ether}();

        assertEq(address(reentrancyAttack).balance, 1 ether);
        assertEq(address(cryptoBank).balance, 0);
    }

    /**
     * @notice Fuzz: for any whole-ETH amount of victim funds, the bank ends up empty.
     * @param victimEth Number of whole ETH deposited by a victim (bounded to 1-100).
     */
    function testFuzz_attackDrainsBank(uint8 victimEth) public {
        uint256 victimDeposit = bound(uint256(victimEth), 1, 100) * 1 ether;
        vm.deal(randomUser1, victimDeposit);
        vm.prank(randomUser1);
        cryptoBank.depositEther{value: victimDeposit}();

        vm.prank(deployAttacker);
        reentrancyAttack.attack{value: 1 ether}();

        assertEq(address(cryptoBank).balance, 0);
        assertEq(address(reentrancyAttack).balance, victimDeposit + 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                         WITHDRAW ATTACKED FUNDS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The owner collects all stolen funds.
     */
    function testWithdrawAttackedFundsOK() public {
        _depositRandomUserFunds();
        vm.startPrank(deployAttacker);
        reentrancyAttack.attack{value: 1 ether}();

        uint256 ownerBalanceBefore = deployAttacker.balance;
        reentrancyAttack.withdrawAttackedFunds();
        vm.stopPrank();

        assertEq(address(reentrancyAttack).balance, 0);
        assertEq(deployAttacker.balance, ownerBalanceBefore + 4 ether);
    }

    /**
     * @notice Only the owner can collect the stolen funds.
     */
    function testWithdrawAttackedFundsKO_notOwner() public {
        vm.prank(randomUser1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, randomUser1));
        reentrancyAttack.withdrawAttackedFunds();
    }

    /**
     * @notice Collecting funds reverts if the owner cannot receive ETH.
     * @dev Ownership is moved to this test contract, which has no `receive`/`fallback`.
     */
    function testWithdrawAttackedFundsKO_transferFailed() public {
        _depositRandomUserFunds();
        vm.startPrank(deployAttacker);
        reentrancyAttack.attack{value: 1 ether}();
        reentrancyAttack.transferOwnership(address(this));
        vm.stopPrank();

        vm.expectRevert("Transfer failed");
        reentrancyAttack.withdrawAttackedFunds();
    }

    /*//////////////////////////////////////////////////////////////
                      CRYPTOBANK FIXED (HAPPY / KO)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice A deposit of at least 1 ETH is credited to the depositor in the fixed bank.
     */
    function testFixedDepositOK() public {
        vm.prank(randomUser1);
        cryptoBankFixed.depositEther{value: 2 ether}();

        assertEq(cryptoBankFixed.userBalance(randomUser1), 2 ether);
        assertEq(address(cryptoBankFixed).balance, 2 ether);
    }

    /**
     * @notice Deposits below 1 ETH revert in the fixed bank.
     */
    function testFixedDepositKO_lessThan1Ether() public {
        vm.prank(randomUser1);
        vm.expectRevert("Minimum deposit is 1 ETH");
        cryptoBankFixed.depositEther{value: 0.5 ether}();
    }

    /**
     * @notice An honest user withdraws their deposit and their balance is reset to zero.
     */
    function testFixedWithdrawOK() public {
        vm.startPrank(randomUser1);
        cryptoBankFixed.depositEther{value: 1 ether}();
        uint256 balanceBefore = randomUser1.balance;
        cryptoBankFixed.withdrawEther();
        vm.stopPrank();

        assertEq(randomUser1.balance, balanceBefore + 1 ether);
        assertEq(cryptoBankFixed.userBalance(randomUser1), 0);
        assertEq(address(cryptoBankFixed).balance, 0);
    }

    /**
     * @notice Withdrawing without a balance of at least 1 ETH reverts in the fixed bank.
     */
    function testFixedWithdrawKO_notEnoughBalance() public {
        vm.prank(randomUser1);
        vm.expectRevert("Not enough balance");
        cryptoBankFixed.withdrawEther();
    }

    /**
     * @notice A second withdrawal in a separate transaction reverts: the balance was reset.
     */
    function testFixedWithdrawKO_withdrawTwice() public {
        vm.startPrank(randomUser1);
        cryptoBankFixed.depositEther{value: 1 ether}();
        cryptoBankFixed.withdrawEther();

        vm.expectRevert("Not enough balance");
        cryptoBankFixed.withdrawEther();
        vm.stopPrank();
    }

    /**
     * @notice Withdrawal reverts when the receiver cannot accept ETH, and the balance reset
     *         is rolled back with it (the user keeps their funds).
     * @dev This test contract has no `receive`/`fallback`, so the low-level call fails.
     */
    function testFixedWithdrawKO_transferFailed() public {
        vm.deal(address(this), 1 ether);
        cryptoBankFixed.depositEther{value: 1 ether}();

        vm.expectRevert("Transfer failed");
        cryptoBankFixed.withdrawEther();

        assertEq(cryptoBankFixed.userBalance(address(this)), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                         ATTACK ON FIXED BANK
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice The reentrancy attack fails against the fixed bank and the whole tx reverts.
     * @dev The re-entrant `withdrawEther` sees a zero balance and reverts with
     *      "Not enough balance". That makes the bank's `call` return false, so the outer
     *      `withdrawEther` bubbles it up as "Transfer failed".
     */
    function testFixedAttackKO_reentrancyBlocked() public {
        _depositRandomUserFundsFixed();
        uint256 attackerBalanceBefore = deployAttacker.balance;

        vm.prank(deployAttacker);
        vm.expectRevert("Transfer failed");
        reentrancyAttackFixed.attack{value: 1 ether}();

        assertEq(address(cryptoBankFixed).balance, 3 ether);
        assertEq(address(reentrancyAttackFixed).balance, 0);
        assertEq(deployAttacker.balance, attackerBalanceBefore);
    }

    /**
     * @notice The attacker does try to re-enter: `withdrawEther` is called twice.
     * @dev `vm.expectRevert` only checks the outermost revert reason, so this test proves
     *      the re-entry attempt happened by counting calls to `withdrawEther`.
     */
    function testFixedAttackKO_reentrantCallAttempted() public {
        _depositRandomUserFundsFixed();

        vm.expectCall(address(cryptoBankFixed), abi.encodeCall(CryptoBankFixed.withdrawEther, ()), 2);
        vm.prank(deployAttacker);
        vm.expectRevert("Transfer failed");
        reentrancyAttackFixed.attack{value: 1 ether}();
    }

    /**
     * @notice Honest users can still withdraw after a failed attack: the bank stays solvent.
     */
    function testFixedAttackKO_victimsCanStillWithdraw() public {
        _depositRandomUserFundsFixed();

        vm.prank(deployAttacker);
        vm.expectRevert("Transfer failed");
        reentrancyAttackFixed.attack{value: 1 ether}();

        uint256 balanceBefore = randomUser1.balance;
        vm.prank(randomUser1);
        cryptoBankFixed.withdrawEther();

        assertEq(randomUser1.balance, balanceBefore + 1 ether);
        assertEq(address(cryptoBankFixed).balance, 2 ether);
    }

    /**
     * @notice With an empty bank the attacker contract does not re-enter and only gets back
     *         its own deposit, like any honest user.
     */
    function testFixedAttackOK_emptyBank() public {
        vm.prank(deployAttacker);
        reentrancyAttackFixed.attack{value: 1 ether}();

        assertEq(address(reentrancyAttackFixed).balance, 1 ether);
        assertEq(address(cryptoBankFixed).balance, 0);
        assertEq(cryptoBankFixed.userBalance(address(reentrancyAttackFixed)), 0);
    }

    /**
     * @notice Fuzz: whatever the victim deposits, the attack on the fixed bank always
     *         reverts and the bank keeps every wei.
     * @param victimEth Number of whole ETH deposited by a victim (bounded to 1-100).
     */
    function testFuzz_fixedAttackNeverDrains(uint8 victimEth) public {
        uint256 victimDeposit = bound(uint256(victimEth), 1, 100) * 1 ether;
        vm.deal(randomUser1, victimDeposit);
        vm.prank(randomUser1);
        cryptoBankFixed.depositEther{value: victimDeposit}();

        vm.prank(deployAttacker);
        vm.expectRevert("Transfer failed");
        reentrancyAttackFixed.attack{value: 1 ether}();

        assertEq(address(cryptoBankFixed).balance, victimDeposit);
        assertEq(cryptoBankFixed.userBalance(randomUser1), victimDeposit);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits 1 ETH from each of the three honest users into the fixed bank.
     */
    function _depositRandomUserFundsFixed() internal {
        vm.prank(randomUser1);
        cryptoBankFixed.depositEther{value: 1 ether}();

        vm.prank(randomUser2);
        cryptoBankFixed.depositEther{value: 1 ether}();

        vm.prank(randomUser3);
        cryptoBankFixed.depositEther{value: 1 ether}();

        assertEq(address(cryptoBankFixed).balance, 3 ether);
    }

    /**
     * @notice Deposits 1 ETH from each of the three honest users (3 ETH total).
     */
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
