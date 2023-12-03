/**
 * Contract for swapping token A for token B at a set exchange rate.
 */

pragma solidity 0.8.10;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

contract Swapper is Ownable, ReentrancyGuard {
    event SwapExecuted(address indexed recipient, uint256 amountTokenA, uint256 amountTokenB);

    ERC20 public tokenA;
    ERC20 public tokenB;

    // Exchange ratio: How much token_B to give back for 1e18 of token_A. 
    uint256 public exchangeRate;

    // Timestamp for end of swap period.
    uint256 public endTime;

    constructor(address _tokenA, address _tokenB, uint256 _exchangeRate, uint256 _lengthActiveSeconds) public {
        tokenA = ERC20(_tokenA);
        tokenB = ERC20(_tokenB);
        exchangeRate = _exchangeRate;
        endTime = block.timestamp + _lengthActiveSeconds;
    }

    function setExchangeRate(uint256 _exchangeRate) external onlyOwner {
        exchangeRate = _exchangeRate;   
    }

    // Swaps tokenA for tokenB.
    function swap(uint256 _amountTokenA) external nonReentrant returns (uint256 _amountTokenB) {
        require(block.timestamp < endTime, "Swap period has ended");
        _amountTokenB = _amountTokenA * exchangeRate / 1e18;
        SafeTransferLib.safeTransferFrom(tokenA, msg.sender, address(this), _amountTokenA);
        SafeTransferLib.safeTransfer(tokenB, msg.sender, _amountTokenB);

        emit SwapExecuted(msg.sender, _amountTokenA, _amountTokenB);
    }

    function sendToken(address _token, address _recipient, uint256 _amount) external onlyOwner {
        SafeTransferLib.safeTransfer(ERC20(_token), _recipient, _amount);
    }
}
