// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20Upgradeable} from "solmate/tokens/ERC20Upgradeable.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ReentrancyGuardUpgradeable} from "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {StringsUpgradeable} from "openzeppelin-contracts-upgradeable/utils/StringsUpgradeable.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IERC2612} from "./interfaces/IERC2612.sol";
import {IWAVAX} from "./interfaces/IWAVAX.sol";


/** 
 * @notice Vault is an ERC20 implementation which deposits a token to a farm or other contract, 
 * and autocompounds in value for all users. If there has been too much time since the last deliberate
 * reinvestment, the next action will automatically be a reinvestent. This contract is inherited from 
 * the Router contract so it can swap to autocompound. It is inherited by various Vault implementations 
 * to specify how rewards are claimed and how tokens are deposited into different protocols. 
 */

contract BareVault is ERC20Upgradeable, ReentrancyGuardUpgradeable, OwnableUpgradeable {
    using SafeTransferLib for IERC20;

    // Min swap to rid of edge cases with untracked rewards for small deposits. 
    uint256 constant public MIN_SWAP = 1e16;
    uint256 constant public MIN_FIRST_MINT = 1e12; // Require substantial first mint to prevent exploits from rounding errors
    uint256 constant public FIRST_DONATION = 1e8; // Lock in first donation to prevent exploits from rounding errors

    uint256 public underlyingDecimal; //decimal of underlying token
    ERC20 public underlying; // the underlying token

    address[] public rewardTokens; //List of reward tokens send to this vault. address(1) indicates raw AVAX
    uint256 public lastReinvestTime; // Timestamp of last reinvestment
    uint256 public maxReinvestStale; //Max amount of time in seconds between a reinvest
    address public feeRecipient; //Owner of admin fee
    uint256 public adminFee; // Fee in bps paid out to admin on each reinvest
    uint256 public callerFee; // Fee in bps paid out to caller on each reinvest
    IWAVAX public WAVAX;

    address public compounder;

    event Reinvested(address caller, uint256 preCompound, uint256 postCompound);
    event CallerFeePaid(address caller, uint256 amount);
    event AdminFeePaid(address caller, uint256 amount);
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event FeesChanged(uint256 adminFee, uint256 callerFee);
    event MaxReinvestStaleChanged(uint256 maxReinvestStale);
    event FeeRecipientChanged(address feerecipient);
    event RewardTokenAdded(address token);
    event RewardTokenDeprecated(address _token);

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event RewardTokenSet(address caller, uint256 index, address rewardToken);
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;

    // Comment for testing purposes
    // constructor() initializer {} todo 

    function initialize(
        address _underlying,
        string memory _name,
        string memory _symbol,
        uint256 _adminFee,
        uint256 _callerFee,
        uint256 _maxReinvestStale,
        address _WAVAX
        ) public virtual initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        initializeERC20(_name, _symbol, 18);
        underlying = ERC20(_underlying);
        underlyingDecimal = underlying.decimals();
        setFee(_adminFee, _callerFee);
        maxReinvestStale = _maxReinvestStale;
        WAVAX = IWAVAX(_WAVAX);
    }
    
    // Sets fee
    function setFee(uint256 _adminFee, uint256 _callerFee) public onlyOwner {
        require(_adminFee + _callerFee < 10000);
        adminFee = _adminFee;
        callerFee = _callerFee;
        emit FeesChanged(_adminFee, _callerFee);
    }

    // Sets the maxReinvest stale
    function setStale(uint256 _maxReinvestStale) external onlyOwner {
        maxReinvestStale = _maxReinvestStale;
        emit MaxReinvestStaleChanged(_maxReinvestStale);
    }

    // Sets fee recipient which will get a certain adminFee percentage of reinvestments. 
    function setFeeRecipient(address _feeRecipient) external onlyOwner {
        feeRecipient = _feeRecipient;
        emit FeeRecipientChanged(_feeRecipient);
    }

    // Add reward token to list of reward tokens
    function pushRewardToken(address _token) external onlyOwner {
        require(address(_token) != address(0), "0 address");
        rewardTokens.push(_token);
        emit RewardTokenAdded(_token);
    }

    // If for some reason a reward token needs to be deprecated it is set to 0
    function deprecateRewardToken(uint256 _index) external onlyOwner {
        require(_index < rewardTokens.length, "Out of bounds");
        address token = rewardTokens[_index];
        rewardTokens[_index] = address(0);
        emit RewardTokenDeprecated(token);
    }

    /**
     * @notice if set to 0 address, that means that there is no designated compounder
     */
    function setCompounder(address _compounder) external onlyOwner {
        compounder = _compounder;
    }

    function numRewardTokens() public view returns (uint256) {
        return rewardTokens.length;
    }

    function getRewardToken(uint256 _ind) public view returns (address) {
        return rewardTokens[_ind];
    }

    // How many vault tokens can I get for 1 unit of the underlying * 1e18
    // Can be overriden if underlying balance is not reflected in contract balance
    function receiptPerUnderlying() public view virtual returns (uint256) {
        if (totalSupply == 0) {
            return 10 ** (18 + 18 - underlyingDecimal);
        }
        return (1e18 * totalSupply) / underlying.balanceOf(address(this));
    }

    // How many underlying tokens can I get for 1 unit of the vault token * 1e18
    // Can be overriden if underlying balance is not reflected in contract balance
    function underlyingPerReceipt() public view virtual returns (uint256) {
        if (totalSupply == 0) {
            return 10 ** underlyingDecimal;
        }
        return (1e18 * underlying.balanceOf(address(this))) / totalSupply;
    }

    // Deposit underlying for a given amount of vault tokens. Buys in at the current receipt
    // per underlying and then transfers it to the original sender. 
    function deposit(address _to, uint256 _amt) public nonReentrant returns (uint256 receiptTokens) {
        require(_amt > 0, "0 tokens");
        // Reinvest if it has been a while since last reinvest
        if (block.timestamp > lastReinvestTime + maxReinvestStale) {
            _compound();
        }
        uint256 _toMint = _preDeposit(_amt);
        receiptTokens = (receiptPerUnderlying() * _toMint) / 1e18;
        if (totalSupply == 0) {
            require(receiptTokens >= MIN_FIRST_MINT);
            _mint(feeRecipient, FIRST_DONATION);
            receiptTokens -= FIRST_DONATION;
        }
        require(
            receiptTokens != 0,
            "0 received"
        );
        _triggerDepositAction(_amt);
        _mint(_to, receiptTokens);
        emit Deposit(msg.sender, _to, _amt, receiptTokens);
    }
    
    function deposit(uint256 _amt) public returns (uint256) {
        return deposit(msg.sender, _amt);
    }

    // Deposit underlying token supporting gasless approvals
    function depositWithPermit(
        uint256 _amt,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public returns (uint256 receiptTokens) {
        IERC2612(address(underlying)).permit(
            msg.sender,
            address(this),
            _value,
            _deadline,
            _v,
            _r,
            _s
        );
        return deposit(_amt);
    }

    // Withdraw underlying tokens for a given amount of vault tokens
    function redeem(address _to, uint256 _amt) public virtual nonReentrant returns (uint256 amtToReturn) {
        // require(_amt > 0, "0 tokens");
        if (block.timestamp > lastReinvestTime + maxReinvestStale) {
            _compound();
        }
        amtToReturn = (underlyingPerReceipt() * _amt) / 1e18;
        _burn(msg.sender, _amt);
        _triggerWithdrawAction(_to, amtToReturn);
        emit Withdraw(msg.sender, _to, msg.sender, amtToReturn, _amt);
    }

    function redeem(uint256 _amt) public returns (uint256) {
        return redeem(msg.sender, _amt);
    }

    // Bailout in case compound() breaks
    function emergencyRedeem(uint256 _amt)
        public nonReentrant
        returns (uint256 amtToReturn)
    {
        amtToReturn = (underlyingPerReceipt() * _amt) / 1e18;
        _burn(msg.sender, _amt);
        _triggerWithdrawAction(msg.sender, amtToReturn);
        emit Withdraw(msg.sender, msg.sender, msg.sender, amtToReturn, _amt);
    }

    function totalHoldings() public virtual returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    // Once underlying has been deposited tokens may need to be invested in a staking thing
    function _triggerDepositAction(uint256 _amt) internal virtual {
        SafeTransferLib.safeTransferFrom(
            underlying,
            msg.sender,
            address(this),
            _amt
        );
    }

    // If a user needs to withdraw underlying, we may need to unstake from something
    function _triggerWithdrawAction(address _to, uint256 _amt)
        internal
        virtual
    {
        SafeTransferLib.safeTransfer(underlying, _to, _amt);
    }

    function _preDeposit(uint256 _amt) internal virtual returns (uint256) {
        return _amt;
    }

    // Function that will pull rewards into the contract
    // Will be overridenn by child classes
    function _pullRewards() internal virtual {
        return;
    }

    function _getValueOfUnderlyingPre() internal virtual returns (uint256) {
        return underlying.balanceOf(address(this));
    }

    function _getValueOfUnderlyingPost() internal virtual returns (uint256) {
        return underlying.balanceOf(address(this));
    }


    function compound() external nonReentrant returns (uint256) {
        return _compound();
    }

    fallback() external payable {
        return;
    }

    // Compounding function
    // Loops through all reward tokens and swaps for underlying using inherited router
    // Pays fee to caller to incentivize compounding
    // Pays fee to admin
    function _compound() internal virtual returns (uint256) {
        lastReinvestTime = block.timestamp;
        _pullRewards();
    }
}
