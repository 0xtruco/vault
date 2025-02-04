#! /bin/bash
set -e
set -o xtrace
#Example: bash -x setRoute.sh route.config address
. $1 # pass config file with relevant addresses as first argument
cd ..
cd ..
cd contracts
RPC="https://api.avax.network/ext/bc/C/rpc"
cast call --private-key $DEPLOYER $2 "setRoute(address,address,(address,uint256,address,address,int128,int128,int128)[])" \

ethabi encode function "setRoute(address,address,(address,uint256,address,address,int128,int128,int128)[])"
$FROMTOKEN \
$TOTOKEN \
"$NODES" \
--rpc-url $RPC
cd ..
cd scripts/mainnet