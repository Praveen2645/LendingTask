// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Context.sol";

interface Token {
    function transfer(address recipient, uint256 amount) external returns (bool);

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
        uint256 extraAmount;
    }

    mapping(address => uint256) private _balances; //keep records of tokens owned
    mapping(address => Borrowers) private _borrowers; //keep records of borrowers

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

    function borrow(uint256 _amount, uint256 _extraAmount, uint256 _ltvRatio) external {
        require(_amount > 0, "Amount should be greater than 0");
        require(
            address(this).balance >= _amount + _extraAmount,
            "Insufficient Ether balance in the contract"
        );

        uint256 collateralValue = calculateCollateralValue(_amount, _extraAmount);
        uint256 loanValue = calculateLoanValue(_amount, _ltvRatio);

        require(
            collateralValue >= loanValue,
            "Insufficient collateral for the loan"
        );

        // Transfer the borrowed Ether to the borrower
        payable(msg.sender).transfer(_amount);

        // Update the borrower's balance
        _balances[msg.sender] += _amount;

        // Store the borrower's details
        _borrowers[msg.sender] = Borrowers(
            msg.sender,
            _amount,
            block.timestamp,
            0,
            _extraAmount
        );
    }

    function repay() external payable {
        uint256 repaymentAmount = msg.value;

        // Check if the borrower has an active loan
        Borrowers storage borrower = _borrowers[msg.sender];
        require(
            borrower.amount > 0 && borrower.borrower == msg.sender,
            "No active loan found"
        );

        // Check if the borrower has enough balance to repay the loan and extra amount
        require(
            _balances[msg.sender] >= repaymentAmount,
            "Insufficient balance to repay"
        );

        // Transfer the repayment amount from the borrower to the contract
        _balances[msg.sender] -= repaymentAmount;
        payable(address(this)).transfer(repaymentAmount);

        // Transfer the extra amount back to the borrower
        payable(msg.sender).transfer(borrower.extraAmount);

        // Transfer the equivalent PBMC tokens from the contract to the borrower
        uint256 pbmcAmount = calculatePBMC(repaymentAmount);
        require(
            PBMCToken.balanceOf(address(this)) >= pbmcAmount,
            "Insufficient PBMC balance in the contract"
        );
        require(
            PBMCToken.transfer(msg.sender, pbmcAmount),
            "Transfer failed"
        );

        // Clear the borrower's details
        delete _borrowers[msg.sender];
    }

    function calculatePBMC(uint256 etherAmount) internal pure returns (uint256) {
        uint256 exchangeRate = 10; // Assume the exchange rate is 10 PBMC per wei
        return etherAmount * exchangeRate;
    }

    function calculateCollateralValue(uint256 amount, uint256 extraAmount) internal view returns (uint256) {
        return address(this).balance + amount + extraAmount;
    }

    function calculateLoanValue(uint256 amount, uint256 ltvRatio) internal pure returns (uint256) {
        require(ltvRatio > 0 && ltvRatio <= 100, "Invalid LTV ratio");

        uint256 loanValue = (amount * 100) / ltvRatio;
        return loanValue;
    }
}
