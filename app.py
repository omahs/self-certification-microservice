from flask import Flask, request, jsonify
import subprocess
import os
from cachetools import TTLCache

app = Flask(__name__)

CONTRACT_HASH = os.getenv('CONTRACT_HASH')
NODE_ADDRESS = os.getenv('NODE_ADDRESS')

cache = TTLCache(maxsize=1000, ttl=7200)

@app.route('/is-certified', methods=['POST'])
def is_certified():
    public_key = request.json.get('public_key')
    if not public_key:
        return jsonify({'error': 'Public key is required'}), 400
    
    if public_key in cache:
        return jsonify({'status': cache[public_key]})

    result, error = query_contract(public_key, NODE_ADDRESS, CONTRACT_HASH)
    if error or result == "False" or result == "null" or result is None:
        cache[public_key] = 'not-certified'
        return jsonify({'status': 'not-certified'})
    else:
        cache[public_key] = result
        return jsonify({'status': result})

def query_contract(public_key, node_address, contract_hash):
    script_path = './get-account-info.sh'
    command = [
        script_path,
        f'--public-key={public_key}',
        f'--node-address={node_address}',
        f'--contract-hash={contract_hash}'
    ]
    
    try:
        result = subprocess.run(command, capture_output=True, text=True, check=True)
        return result.stdout.strip(), None
    except subprocess.CalledProcessError as e:
        return None, e.stderr

if __name__ == '__main__':
    app.run()

