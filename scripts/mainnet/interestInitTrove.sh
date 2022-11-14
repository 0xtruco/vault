#! /bin/bash 
set -o xtrace

REG1="(?:Address: )((?:0x)[a-fA-F0-9]{40})"
# REG2="(?:Private Key: )([a-f0-9]{64})"
RPC="https://api.avax.network/ext/bc/C/rpc"
# RPC="https://api.avax-test.network/ext/bc/C/rpc"


TROVE_MANAGER="0x000000000000614c27530d24B5f039EC15A61d8d"

# Call first
# $(cast send $TROVE_MANAGER "interest_init()" --private-key $DEPLOYER2 --rpc-url $RPC)

# Print AVAX Balance and token balance
# echo "AVAX Balance" $(cast balance $SENDER_ADDRESS --rpc-url $RPC)
# echo "Token Balance" $(cast call $TOKEN "balanceOf(address)(uint256)" $SENDER_ADDRESS --rpc-url $RPC)

# Create addresses.csv file which will store the addresses which have been processed already.
echo "Address" > addresses.csv

N_TROVE_OWNERS=$(cast call $TROVE_MANAGER "getTroveOwnersCount()(uint256)" --rpc-url $RPC)

echo "Currently there are $N_TROVE_OWNERS troves"

for ((i=0; i<$N_TROVE_OWNERS; i++))
do 
    echo $i
    # Fetch wallet from trove manager list
    WALLET=$(cast call $TROVE_MANAGER "getTroveFromTroveOwnersArray(uint256)(address)" $i --rpc-url $RPC)
    echo "Updating interest to account $i and wallet $WALLET"

    $(cast send $TROVE_MANAGER "interestInitTrove(address)" $WALLET --private-key $DEPLOYER2 --rpc-url $RPC)
    
    # Store wallet in output file addresses.csv
    echo $WALLET | tr ", " >> addresses.csv
done





