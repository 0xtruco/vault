// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "src/interfaces/IYetiGLPMinter.sol";
import "src/interfaces/IGMXRewardRouter.sol";
import "src/interfaces/IERC20.sol";
import "src/interfaces/IGLPManager.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @notice Different minter address due to the mint and send window of currently 15 minutes. 
 * The GLP Vault contract will have special permissions for the only external function, mintGLP. 
 * If we assume compound() is called once per day, then actual rewards will lag behind 
 * by one day, which after the first day is equivalent anyway. 
 */

contract YetiGLPMinter is IYetiGLPMinter, Initializable {
    using SafeTransferLib for IERC20;

    address public GLPVault;

    IGMXRewardRouter public constant GMXRewardRouter = IGMXRewardRouter(0x82147C5A7E850eA4E28155DF107F2590fD4ba327);

    address public constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    address public constant fsGLP = 0x9e295B5B976a184B14aD8cd72413aD846C299660;

    ERC20 public constant sGLP = ERC20(0x0b82a1aD2138E9f62454ac41b702B64e0b73d57b);

    uint256 public nextValidMintTimestamp;

    // GLP Manager contract, used for functionality like checking the cooldown duration
    // Currently cooldown duration is set to 15 minutes. 
    IGLPManager public constant GLPManager = IGLPManager(0xe1ae4d4b06A5Fe1fc288f6B4CD72f9F8323B107F);

    // Comment for testing purposes
    constructor() initializer {}

    function initialize(address _GLPVault) public initializer {
        GLPVault = _GLPVault;
        // Approve WAVAX for later use by GMX Reward Router. Actually pulled in by GLP Manager
        // contract. 
        ERC20(WAVAX).approve(address(GLPManager), type(uint256).max);
    }

    /** 
     * @notice Mints GLP from this address. Sends to the main GLP vault address when ready
     * There is currently a 15 minute window where a certain address cannot send or sell
     * their GLP. 
     * @param _minGLP The minimum amount of GLP that we should expect to get back. 
     * The amount of WAVAX is just the amount that is held in this contract. 
     */
    function mintGLP(uint256 _minGLP) external override {
        require(msg.sender == GLPVault, "Only GLPVault can call this function");

        // Send amount from last mint, if it has been 15 minutes or more. Otherwise, just
        // skip it. Therefore the next transaction (as long as 15 mins since last mint) will 
        // go through instead. We are working in small time intervals if this is an issue, 
        // so there will just be periods of no compounding. 
        if (block.timestamp < nextValidMintTimestamp) {
            return;
        }

        // Transfer GLP to the main GLP Vault first. 
        uint256 amountToSendGLP = IERC20(fsGLP).balanceOf(address(this));
        if (amountToSendGLP != 0) {
            SafeTransferLib.safeTransfer(sGLP, GLPVault, amountToSendGLP);
        }

        // Mint with WAVAX amount, equivalent of GLP. Wait to mint also since
        // This could reset the timer otherwise, and there would be a scenario
        // where rewards cannot be claimed from this contract. 
        uint256 amountToMintWAVAX = IERC20(WAVAX).balanceOf(address(this));
        if (amountToMintWAVAX == 0) {
            return;
        }

        // Mint GLP to this address
        GMXRewardRouter.mintAndStakeGlp(WAVAX, amountToMintWAVAX, 0, _minGLP);

        // Update next valid mint timestamp to 15 minutes from now. 
        nextValidMintTimestamp = block.timestamp + GLPManager.cooldownDuration();
    }
}
