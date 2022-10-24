pragma solidity >0.8.0;

/**
 * @notice Used to mint and hold tokens so that withdrawals can work simultaneously with minting
 * since there is a per-account mint limit for GLP itself. 
 */
interface IYetiGLPMinter {
    function mintGLP(uint256 _minGLP) external;
}
