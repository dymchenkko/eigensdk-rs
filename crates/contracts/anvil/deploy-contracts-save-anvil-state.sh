#!/bin/bash

# Enable the script to exit immediately if a command exits with a non-zero status
set -o errexit -o nounset -o pipefail

# cd to the directory of this script so that this can be run from anywhere
anvil_dir=$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd -P
)
root_dir=$(realpath $anvil_dir/../..)

set -a
source $anvil_dir/utils.sh
# we overwrite some variables here because should always deploy to anvil (localhost)
ETH_HTTP_URL=http://localhost:8545
DEPLOYER_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
set +a

# start an empty anvil chain in the background and dump its state to a json file upon exit
start_anvil_docker "" $anvil_dir/contracts_deployed_anvil_state.json
sleep 1

CHAIN_ID=$(cast chain-id)

# DEPLOY CONTRACT REGISTRY
cd $root_dir/contracts
forge create src/ContractsRegistry.sol:ContractsRegistry --rpc-url $ETH_HTTP_URL --private-key $DEPLOYER_PRIVATE_KEY --broadcast


# DEPLOY EIGENLAYER
EIGEN_CONTRACTS_DIR=$root_dir/contracts/lib/eigenlayer-middleware/lib/eigenlayer-contracts
DEVNET_OUTPUT_DIR=$EIGEN_CONTRACTS_DIR/script/output/devnet
cd $EIGEN_CONTRACTS_DIR
forge script script/deploy/local/Deploy_From_Scratch.s.sol:DeployFromScratch --rpc-url $ETH_HTTP_URL \
    --private-key $DEPLOYER_PRIVATE_KEY --broadcast \
    --sig "run(string memory configFileName)" -- local/deploy_from_scratch.anvil.config.json
mv $DEVNET_OUTPUT_DIR/local_from_scratch_deployment_data.json $root_dir/contracts/script/output/${CHAIN_ID:?}/eigenlayer_deployment_output.json

# DEPLOY MOCKAVS
cd $root_dir/contracts
forge script script/DeployMockAvs.s.sol --rpc-url $ETH_HTTP_URL --private-key $DEPLOYER_PRIVATE_KEY --broadcast

# DEPLOY TOKENS AND STRATEGIES
cd $root_dir/contracts
# DO NOT REMOVE THE SLOW DIRECTIVE FROM THIS SCRIPT INVOCATION
# slow ensures that the transaction receipt is successful and received before sending the next transaction
# this should prevent the strategies deploying/registering in a flakey manner,
forge script script/DeployTokensStrategiesCreateQuorums.s.sol --rpc-url $ETH_HTTP_URL --private-key $DEPLOYER_PRIVATE_KEY --broadcast --slow

# REGISTER OPERATORS WITH EIGENLAYER
cd $root_dir/contracts
# DO NOT REMOVE THE SLOW DIRECTIVE FROM THIS SCRIPT INVOCATION
# slow ensures that the transaction receipt is successful and received before sending the next transaction
# this should prevent the operators registering in a flakey manner, the operators registered will change from run to run without this
forge script script/RegisterOperatorsWithEigenlayer.s.sol --rpc-url $ETH_HTTP_URL --private-key $DEPLOYER_PRIVATE_KEY --broadcast --slow

forge script script/UpdateOperators.s.sol --rpc-url $ETH_HTTP_URL --private-key $DEPLOYER_PRIVATE_KEY --broadcast --slow
