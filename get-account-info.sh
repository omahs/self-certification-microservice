#!/bin/bash

print_usage () {
  echo "USAGE:"
  echo "  get-account-info.sh [ARGUMENTS]"
  echo
  echo "ARGUMENTS:"
  echo "  --node-address   Casper node to run RPC requests against (default: 127.0.0.1)"
  echo "  --contract-hash  Account info contract hash without the 'hash--' prefix (default: 2f36a35edcbaabe17aba805e3fae42699a2bb80c2e0c15189756fdc4895356f8, account info contract hash on the Testnet)"
  echo "  --public-key     Account public key in the hex format"
  echo
  echo "EXAMPLE:"
  echo "  get-account-info.sh --public-key=0106ca7c39cd272dbf21a86eeb3b36b7c26e2e9b94af64292419f7862936bca2ca"
  echo
  echo "DEPENDENCIES:"
  echo "  casper-client    To make RPC requests to the network"
  echo "  jq               To parse RPC responses"
  echo "  curl             To fetch account information"
  echo "  sed              To manipulate strings"
}

ensure_has_installed () {
  HAS_INSTALLED=$(which "$1")
  if [ "$HAS_INSTALLED" = "" ]; then
    echo "Please install $1"
    exit 1
  fi
}

ensure_has_installed "casper-client"
ensure_has_installed "curl"
ensure_has_installed "jq"
ensure_has_installed "sed"

while [ $# -gt 0 ]; do
  case "$1" in
    --node-address=*)
      NODE_ADDRESS="${1#*=}"
      ;;
    --contract-hash=*)
      CONTRACT_HASH="${1#*=}"
      ;;
    --public-key=*)
      PUBLIC_KEY="${1#*=}"
      ;;
    *)
      print_usage; exit 1
      ;;
  esac
  shift
done

if [ -z ${NODE_ADDRESS+x} ]; then NODE_ADDRESS=34.224.191.55; fi
if [ -z ${CONTRACT_HASH+x} ]; then CONTRACT_HASH=fb8e0215c040691e9bbe945dd22a00989b532b9c2521582538edb95b61156698; fi
if [ -z ${PUBLIC_KEY+x} ]; then print_usage; exit 1; fi

STATE_ROOT_HASH=$(casper-client get-state-root-hash --node-address http://$NODE_ADDRESS:7777 | jq -r '.result | .state_root_hash' 2>&1)
if [[ $? -ne 0 ]]; then
  echo "Error fetching state root hash: $STATE_ROOT_HASH"
  exit 1
fi

ACCOUNT_INFO_URLS_DICT_UREF=$(casper-client query-state \
  --node-address http://$NODE_ADDRESS:7777 \
  --state-root-hash "$STATE_ROOT_HASH" \
  --key "hash-$CONTRACT_HASH" \
| jq -rc '.result | .stored_value | .Contract | .named_keys | map(select(.name | contains("account-info-urls"))) | .[] .key' 2>&1)
if [[ $? -ne 0 ]]; then
  echo "Error fetching account info URLs dictionary UREF: $ACCOUNT_INFO_URLS_DICT_UREF"
  exit 1
fi

ACCOUNT_HASH=$(casper-client account-address --public-key $PUBLIC_KEY | sed -r 's/account-hash-//g')
ACCOUNT_HASH_LOWERCASED=$(echo $ACCOUNT_HASH | tr '[:upper:]' '[:lower:]')

BASE_URL=$(casper-client get-dictionary-item \
  --node-address http://$NODE_ADDRESS:7777 \
  --state-root-hash "$STATE_ROOT_HASH" \
  --seed-uref  "$ACCOUNT_INFO_URLS_DICT_UREF" \
  --dictionary-item-key "$ACCOUNT_HASH_LOWERCASED" \
| jq -r '.result | .stored_value | .CLValue | .parsed' 2>&1)
if [[ $? -ne 0 ]]; then
  echo "Error fetching base URL: $BASE_URL"
  exit 1
fi

CHAIN_NAME=$(curl -s http://$NODE_ADDRESS:8888/status | jq -r '.chainspec_name' 2>&1)
if [[ $? -ne 0 ]]; then
  echo "Error fetching chain name: $CHAIN_NAME"
  exit 1
fi

if [ "$BASE_URL" = "null" ]; then
  echo "Account information URL is not set for the given public key on the $CHAIN_NAME network"
  exit 0
else
  curl -s "$BASE_URL/.well-known/casper/account-info.$CHAIN_NAME.json"
fi
