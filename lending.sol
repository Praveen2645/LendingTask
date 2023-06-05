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
        uint256 startTime;
        uint256 interestRate;
        
    }

    mapping(address => uint256) private _tokenBalances; //keep records of tokens owned
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
        _tokenBalances[msg.sender] += pbmcAmount;
    }

    function borrow(uint256 _tokenAmount) external {
        require(_tokenAmount > 0, "Amount should be greater than 0");
        require(
            PBMCToken.balanceOf(msg.sender) >= _tokenAmount,
            "Insufficient PBMC balance"
        );

        // Transfer the PBMC coins from the borrower to the contract
        require(
            PBMCToken.transferFrom(msg.sender, address(this), _tokenAmount),
            "PBMC transfer failed"
        );

        // Calculate the equivalent amount of ethers to transfer
        uint256 etherAmount = calculateEtherAmount(_tokenAmount);

        // Transfer the ethers to the borrower
        payable(msg.sender).transfer(etherAmount);

        // Update the borrower's balance
        _tokenBalances[msg.sender] += etherAmount;

        // Store the borrower's details
        _borrowers[msg.sender] = Borrowers(
            msg.sender,
            etherAmount,
            block.timestamp,
            0
        );
    }

    function repay() external payable {
        // Check if the borrower has an active loan
        Borrowers storage borrower = _borrowers[msg.sender];
        require(
            borrower.amount > 0 && borrower.borrower == msg.sender,
            "No active loan found"
        );

        uint256 repaymentAmount = msg.value;

        // Calculate the equivalent amount of PBMC tokens to return
        uint256 pbmcAmount = calculatePBMC(repaymentAmount);

        // Check if the contract has enough PBMC tokens to return
        require(
            PBMCToken.balanceOf(address(this)) >= pbmcAmount,
            "Insufficient PBMC balance in the contract"
        );

        // Transfer the equivalent PBMC tokens from the contract to the borrower
        require(
            PBMCToken.transfer(msg.sender, pbmcAmount),
            "Transfer failed"
        );

        // Clear the borrower's details
        delete _borrowers[msg.sender];

        // Transfer any remaining excess ether back to the borrower
        if (msg.value > repaymentAmount) {
            uint256 excessAmount = msg.value - repaymentAmount;
            payable(msg.sender).transfer(excessAmount);
        }
    }

    function calculatePBMC(uint256 etherAmount) internal pure returns (uint256) {
        uint256 exchangeRate = 10; // Assume the exchange rate is 10 PBMC per wei
        return etherAmount * exchangeRate;
    }

    function calculateEtherAmount(uint256 pbmcAmount)
        internal
        pure
        returns (uint256)
    {
        uint256 exchangeRate = 10; // Assume the exchange rate is 10 PBMC per wei
        return pbmcAmount / exchangeRate;
    }
}
