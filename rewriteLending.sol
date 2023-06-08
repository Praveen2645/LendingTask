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
    uint256 monthlyInterest = 10;
    uint256 tokenId = 1;
    uint256 annualYield = 5;

    function initializeAddresses(Token _tokenAddress, address _priceFeedAddress)
        external
        onlyOwner
    {
        require(
            address(_tokenAddress) != address(0),
            "Token Address cannot be address 0"
        );
        PBMCToken = _tokenAddress;
        // Initialize the Chainlink price feed
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
    }

    struct token {
        uint256 LTVPercentage;
        bool active;
    }

    struct Lenders {
        uint256 lendedAmount;
        uint256 PBMCInReturn;
        uint256 startTime;
        uint256 monthlyReward;
        uint256 annualYield;
    }

    struct Borrowers {
        uint256 PBMCdeposited;
        uint256 etherInReturn;
        uint256 startTime;
        uint256 monthlyInterest;
        bool active;
    }

    mapping(uint256 => token) public _idToToken;
    mapping(address => mapping(uint256 => Borrowers)) public _borrowers;
    mapping(address => Lenders) public _lenders; // keep records of lenders

    function createLTV(uint256 _LTVratio) external returns(bool){
        _idToToken[tokenId] = token(_LTVratio,true);
        tokenId++;
        return true;
    }

    function lend(uint256 _amount) external payable {
        require(_amount > 0, "Amount must be greater than zero");
        uint256 pbmcAmount = calculatePBMC(_amount);
        require(
            PBMCToken.balanceOf(address(this)) >= pbmcAmount, //checking the pbmc balance of contract for transferinig PBMC to lender
            "Insufficient PBMC balance in the contract"
        );
        // Transfer the PBMC coins to the lender
        PBMCToken.transfer(msg.sender, pbmcAmount);
        uint256 interestEarned = (msg.value * monthlyInterest) / 100; //owner can change interest rate
        _lenders[msg.sender] = Lenders(
            _amount,
            pbmcAmount,
            block.timestamp,
            interestEarned,
            5 
        );
    }

    function borrow(uint256 _tokenAmount, uint _tokenId) external {
       // Borrowers storage borrower = _borrowers[msg.sender][_tokenId];
        require(_tokenAmount > 0, "Amount should be greater than 0");
         require(
             PBMCToken.balanceOf(msg.sender) > 0, //check for caller has token or not
            "Insufficient PBMC balance"
         );
       
        PBMCToken.transferFrom(msg.sender, address(this), _tokenAmount);

        // Calculate the equivalent amount of ethers to transfer
        uint256 etherAmount = calculateEtherAmount(_tokenAmount);

        // Transfer the ethers to the borrower
        payable(msg.sender).transfer(etherAmount);

        // Store the borrower's details
        _borrowers[msg.sender][_tokenId] = Borrowers(
            _tokenAmount,
            etherAmount,
            block.timestamp,
            monthlyInterest,
            true
        );
        
    }

    function repay(uint256 _amount, uint _tokenId) external payable {
        Borrowers storage borrower = _borrowers[msg.sender][_tokenId]; // fetch from strcut
        require(_amount>0,"please pay the amount greater than zero");
        require(borrower.active == true, "no such plan");
        require(borrower.active == false, "you have already staked ");

        // Calculate the equivalent amount of PBMC tokens to return based on the amount being repaid
        uint256 pbmcAmount = calculatePBMC(_amount);

        // Check if the contract has enough PBMC tokens to return
        require(
            PBMCToken.balanceOf(address(this)) >= pbmcAmount,
            "Insufficient PBMC balance in the contract"
        );

        // Transfer the equivalent PBMC tokens from the contract to the borrower
        require(PBMCToken.transfer(msg.sender, pbmcAmount), "Transfer failed");

        // Update the borrower's balance and amount remaining
        //_tokenBalances[msg.sender] -= _amount;
        borrower.PBMCdeposited -= pbmcAmount;

        // Transfer any remaining excess ether back to the borrower
        if (msg.value > _amount) {
            uint256 excessAmount = msg.value - _amount;
            payable(msg.sender).transfer(excessAmount);
        }
    }

    // function withdraw() external payable {
    //     Lenders storage lender = _lenders[msg.sender];
    //     //require(lender.lender == msg.sender, "No lending found");
    //     require(lender.lendedAmount > 0, "No amount to withdraw");

    //     uint256 amountToWithdraw = lender.lendedAmount + lender.monthlyInterest;

    //     // Transfer the deposited ethers + interest to the lender
    //     payable(msg.sender).transfer(amountToWithdraw);

    //     // Transfer the PBMC tokens owned in exchange back to the contract owner
    //     require(
    //         PBMCToken.transferFrom(msg.sender, owner(), lender.PBMCInReturn),
    //         "PBMC transfer failed"
    //     );

    //     // Reset the lender's details
    //     delete _lenders[msg.sender];
    // }

    function calculatePBMC(uint256 etherAmount) private view returns (uint256) {
        uint256 etherPriceInUSD = getCurrentEtherPrice();
        uint256 pbmcPriceInUSD = 5;
        uint256 pbmcAmount = (etherAmount * etherPriceInUSD) / pbmcPriceInUSD;
        return pbmcAmount;
    }

    function calculateEtherAmount(uint256 pbmcAmount)
        private
        view
        returns (uint256)
    {
        uint256 etherPriceInUSD = getCurrentEtherPrice();
        uint256 pbmcPriceInUSD = 5;
        uint256 etherAmount = (pbmcAmount * pbmcPriceInUSD) / etherPriceInUSD;
        return etherAmount;
    }

    //function to get the current ether price
    function getCurrentEtherPrice() public view returns (uint256) {
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function calculateLoanAmount(uint256 productId, uint256 collateralValue)
        public
        view
        returns (uint256)
    {
        require(productId > 0 && productId <= 3, "Invalid loan product ID"); // Assuming we have 3 loan products
        token memory tokens = _idToToken[tokenId];
        return (collateralValue * tokens.LTVPercentage) / 100;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
