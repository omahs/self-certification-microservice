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

is_valid_json() {
  echo "$1" | jq . > /dev/null 2>&1
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

STATE_ROOT_HASH_JSON=$(casper-client get-state-root-hash --node-address http://$NODE_ADDRESS:7777 2>&1)
if ! is_valid_json "$STATE_ROOT_HASH_JSON"; then
  echo "False"
  exit 1
fi
STATE_ROOT_HASH=$(echo "$STATE_ROOT_HASH_JSON" | jq -r '.result | .state_root_hash')

ACCOUNT_INFO_URLS_DICT_UREF_JSON=$(casper-client query-state \
  --node-address http://$NODE_ADDRESS:7777 \
  --state-root-hash "$STATE_ROOT_HASH" \
  --key "hash-$CONTRACT_HASH" 2>&1)
if ! is_valid_json "$ACCOUNT_INFO_URLS_DICT_UREF_JSON"; then
  echo "False"
  exit 1
fi
ACCOUNT_INFO_URLS_DICT_UREF=$(echo "$ACCOUNT_INFO_URLS_DICT_UREF_JSON" | jq -rc '.result | .stored_value | .Contract | .named_keys | map(select(.name | contains("account-info-urls"))) | .[] .key')

ACCOUNT_HASH=$(casper-client account-address --public-key $PUBLIC_KEY | sed -r 's/account-hash-//g')
ACCOUNT_HASH_LOWERCASED=$(echo $ACCOUNT_HASH | tr '[:upper:]' '[:lower:]')

BASE_URL_JSON=$(casper-client get-dictionary-item \
  --node-address http://$NODE_ADDRESS:7777 \
  --state-root-hash "$STATE_ROOT_HASH" \
  --seed-uref  "$ACCOUNT_INFO_URLS_DICT_UREF" \
  --dictionary-item-key "$ACCOUNT_HASH_LOWERCASED" 2>&1)
if ! is_valid_json "$BASE_URL_JSON"; then
  echo "False"
  exit 1
fi
BASE_URL=$(echo "$BASE_URL_JSON" | jq -r '.result | .stored_value | .CLValue | .parsed')

if [[ "$BASE_URL" == "null" ]]; then
  echo "False"
  exit 1
fi

echo "$BASE_URL"
