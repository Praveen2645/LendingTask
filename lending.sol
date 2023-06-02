// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Context.sol";

interface Token {
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

contract LendingAndBorrowing is Ownable, ReentrancyGuard, Pausable {
    Token PBMCToken;

    constructor(Token _tokenAddress) {
        require(
            address(_tokenAddress) != address(0),
            "Token Address cannot be address 0"
        );
        PBMCToken = _tokenAddress;
    }

    address[] public lenders;

    struct Borrowers {
        address borrower;
        uint256 amount;
        uint256 term;
        uint256 interestRate;
    }

    mapping(address => uint256)  _balances; //keep records of tokens owned

    function lend() external payable {
        require(msg.value > 0, "Amount must be greater than zero");
        uint256 pbmcAmount = calculatePBMC(msg.value);

        require(
            PBMCToken.balanceOf(address(this)) >= pbmcAmount,
            "Insufficient PBMC balance in the contract"
        );

        // Transfer the PBMC coins to the lender
        require(PBMCToken.transfer(msg.sender, pbmcAmount), "Transfer failed");

        // Update the lender's balance
        _balances[msg.sender] += pbmcAmount;
    }

    function borrow(uint256 _amount) external {
        require(_amount > 0, "Amount should be greater than 0");
        require(
            address(this).balance >= _amount,
            "Insufficient Ether balance in the contract"
        );

        // Transfer the borrowed Ether to the borrower
        payable(msg.sender).transfer(_amount);

        // Update the borrower's balance
        _balances[msg.sender] += _amount;
    }

    function calculatePBMC(uint256 etherAmount)
        internal
        pure
        returns (uint256)
    {
        uint256 exchangeRate = 10; // Assume the exchange rate is 10 PBMC per wei
        return etherAmount * exchangeRate;
    }
    function repay() external  payable {


    }
}
