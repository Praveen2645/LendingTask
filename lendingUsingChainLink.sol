// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


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
    AggregatorV3Interface internal priceFeed;

    Token PBMCToken;

    uint256 interestRate;

   constructor(Token _tokenAddress, address _priceFeedAddress) {

    require(address(_tokenAddress) != address(0), "Token Address cannot be address 0");
    interestRate = 10;
    PBMCToken = _tokenAddress;

    // Initialize the Chainlink price feed
    priceFeed = AggregatorV3Interface(_priceFeedAddress);
}


    address[] public lenders;
    address[] public borrowers;

    struct Lenders {
        address lender;
        uint256 lendedAmount;
        uint256 PBMCinReturn;
        uint256 startTime;
        uint256 interestEarned;
    }

    struct Borrowers {
        address borrower;
        uint256 PBMCdeposited;
        uint256 amountGetInWei;
        uint256 startTime;
    }

    mapping(address => uint256) public _tokenBalances; //keep records of tokens owned
    mapping(address => Borrowers) public _borrowers; //keep records of borrowers
    mapping(address => Lenders) public _lenders; // keep records of lenders

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
         uint256 interestEarned = (msg.value * interestRate) / 100;

        _lenders[msg.sender] = Lenders(
            msg.sender,
            msg.value,
            pbmcAmount,
            block.timestamp,
            interestEarned
        );
        lenders.push(msg.sender);
    }

    function borrow(uint256 _PBMC) external {
        require(_PBMC > 0, "Amount should be greater than 0");
        require(
            PBMCToken.balanceOf(msg.sender) >= _PBMC, //check for caller has token or not
            "Insufficient PBMC balance"
        );
        // Transfer the PBMC coins from the borrower to the contract
        require(
            PBMCToken.transferFrom(msg.sender, address(this), _PBMC),
            "PBMC transfer failed"
        );

        // Calculate the equivalent amount of ethers to transfer
        uint256 etherAmount = calculateEtherAmount(_PBMC);

        // Transfer the ethers to the borrower
        payable(msg.sender).transfer(etherAmount);

        // Update the borrower's balance
        _tokenBalances[msg.sender] += etherAmount;
       
        // Store the borrower's details
        _borrowers[msg.sender] = Borrowers(
            msg.sender,
            _PBMC,
            etherAmount,
            block.timestamp
        );
        borrowers.push(msg.sender);
    }

    function repay() external payable {
        // Check if the borrower has an active loan
        Borrowers storage borrower = _borrowers[msg.sender];
        require(
            borrower.PBMCdeposited> 0 && borrower.borrower == msg.sender,
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
        require(PBMCToken.transfer(msg.sender, pbmcAmount), "Transfer failed");

        // Clear the borrower's details
        delete _borrowers[msg.sender];

        // Transfer any remaining excess ether back to the borrower
        if (msg.value > repaymentAmount) {
            uint256 excessAmount = msg.value - repaymentAmount;
            payable(msg.sender).transfer(excessAmount);
        }
    }

    function calculatePBMC(uint256 etherAmount) private pure returns (uint256) {
        uint256 exchangeRate = 2; // Assume the exchange rate is 10 PBMC per wei
        return etherAmount * exchangeRate;
    }

    function calculateEtherAmount(uint256 pbmcAmount)
        private
        pure
        returns (uint256)
    {
        //uint256 exchangeRate = 1; // 2 PBMC will return 1 wei
        return pbmcAmount / 2;
    }

     function withdraw() external payable{
    Lenders storage lender = _lenders[msg.sender];
    require(lender.lender == msg.sender, "No lending found");
    require(lender.lendedAmount > 0, "No amount to withdraw");

    uint256 amountToWithdraw = lender.lendedAmount + lender.interestEarned;

    // Transfer the deposited ethers + interest to the lender
    payable(msg.sender).transfer(amountToWithdraw);

    // Transfer the PBMC tokens owned in exchange back to the contract owner
    require(
        PBMCToken.transferFrom(msg.sender, owner(), lender.PBMCinReturn),
        "PBMC transfer failed"
    );

    // Reset the lender's details
    delete _lenders[msg.sender];
}
function getCurrentEtherPrice() public view returns (uint256) {
    (, int256 price, , , ) = priceFeed.latestRoundData();
    return uint256(price);
}

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
