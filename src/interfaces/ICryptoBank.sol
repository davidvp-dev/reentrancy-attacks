// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

interface ICryptoBank {
    function depositEther() external payable;
    function withdrawEther() external;
}
