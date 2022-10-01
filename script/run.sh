#! /usr/bin/env bash

FILE_PATH=$1
CONTRACT=$2

set -e

echo "Run script ${CONTRACT} from file ${FILE_PATH}"

source .env && forge script ${FILE_PATH}:${CONTRACT} \
  --fork-url $ETH_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY \
  --optimize \
  --optimizer-runs 200 \
  -vvv
