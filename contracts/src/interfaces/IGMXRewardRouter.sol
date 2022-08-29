pragma solidity >0.8.0;

interface IGMXRewardRouter {

    /** 
     * @notice Claims rewards from GMX Router, such as from staking GLP. 
     * We should do: 1, 1, 1, 1, 1, 1, 0. We want WAVAX instead of 
     * AVAX as rewards. 
     */
    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;

    /**
     * @notice used for minting and staking GLP using a token. In this case we use WAVAX. 
     * _minUsdg will be 0. 
     */
    function mintAndStakeGlp(address _token, uint256 _amount, uint256 _minUsdg, uint256 _minGlp) external returns (uint256);
}
