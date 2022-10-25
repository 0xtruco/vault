#!/bin/bash
set -e
set -o xtrace
cd ..
cd ..
cd contracts
export FOUNDRY_OPTIMIZER_RUNS=200
RPC="https://api.avax.network/ext/bc/C/rpc"
forge build --force
forge config
CREATION=$(forge create src/integrations/stargateVault.sol:stargateVault --rpc-url $RPC --private-key $DEPLOYER --verify)
REG="(?:Deployed to: )((?:0x)[a-f0-9]{40})"
export DEPLOYED=$(echo "$CREATION" | pcregrep -o1 "$REG")
echo $DEPLOYED
forge flatten src/integrations/stargateVault.sol > stargateVault.txt
# VERIFY=$(forge verify-contract --chain-id 43114 --num-of-optimizations $FOUNDRY_OPTIMIZER_RUNS --compiler-version v0.8.10+commit.fc410830 $DEPLOYED src/integrations/stargateVault.sol:stargateVault $ETHERSCAN)
REG2="(?:GUID: \`)([a-z0-9]{50})\`$"
export GUID=$(echo "$CREATION" | pcregrep -o1 "$REG2")
forge verify-check --chain-id 43114 $GUID $ETHERSCAN
cd ..
cd scripts/mainnet
