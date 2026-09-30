#!/usr/bin/env python3
"""Broadcast and settle a local mock lifecycle. Never targets public chains."""
import json
import os
from pathlib import Path
import subprocess
import urllib.request
from urllib.parse import urlsplit

RPC = os.environ.get('ANVIL_RPC_URL', 'http://127.0.0.1:8545')
SENDER = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266'
MAX = str(2**256 - 1)
endpoint = urlsplit(RPC)
if endpoint.scheme != 'http' or endpoint.hostname not in ('127.0.0.1', '::1') or endpoint.username or endpoint.password:
    raise RuntimeError('A literal loopback HTTP Anvil endpoint is required')

def check(condition, message):
    if not condition:
        raise RuntimeError(message)

def run(*args):
    result = subprocess.run(args, check=True, capture_output=True, text=True)
    return result.stdout.strip()

def call(address, signature, *args):
    return int(run('cast', 'call', address, signature, *args, '--rpc-url', RPC).split()[0])

def send(address, signature, *args):
    run('cast', 'send', address, signature, *args, '--rpc-url', RPC, '--unlocked', '--from', SENDER)

def rpc(method, params):
    data = json.dumps({'jsonrpc':'2.0','id':1,'method':method,'params':params}).encode()
    with urllib.request.urlopen(urllib.request.Request(RPC, data=data, headers={'Content-Type':'application/json'})) as response:
        value = json.load(response)
    if 'error' in value:
        raise RuntimeError(value['error'])
    return value['result']

check(int(run('cast', 'chain-id', '--rpc-url', RPC)) == 31337, 'Local chain 31337 required')
# Anvil-specific method must exist before any broadcast.
rpc('anvil_nodeInfo', [])
run('forge', 'script', 'scripts/Deploy.s.sol', '--rpc-url', RPC, '--broadcast', '--unlocked', '--sender', SENDER)
record = json.loads(Path('broadcast/Deploy.s.sol/31337/run-latest.json').read_text())
created = [t for t in record['transactions'] if t.get('transactionType') == 'CREATE']
pool = next(t['contractAddress'] for t in created if t['contractName'] == 'Pool')
tokens = [t['contractAddress'] for t in created if t['contractName'] == 'MockERC20']
check(len(tokens) == 3, 'Three mock tokens required')
usdt, weth, _ = tokens
usd = run('cast', 'keccak', 'mUSDT')
eth = run('cast', 'keccak', 'mWETH')
for token in (usdt, weth):
    send(token, 'approve(address,uint256)', pool, MAX)
send(pool, 'deposit(bytes32,uint256)', usd, str(100_000 * 10**18))
send(pool, 'deposit(bytes32,uint256)', eth, str(10 * 10**18))
send(pool, 'borrow(bytes32,bytes32,uint256,uint256)', eth, usd, str(20_000 * 10**18), str(5 * 10**16))
check(call(pool, 'getPositionDebt(address,uint256)(uint256)', SENDER, '0') >= 20_000 * 10**18, 'Issued debt missing')
rpc('evm_increaseTime', [86400])
rpc('evm_mine', [])
check(call(pool, 'getPositionDebt(address,uint256)(uint256)', SENDER, '0') > 20_000 * 10**18, 'Idle debt did not accrue')
send(pool, 'repay(bytes32,bytes32,uint256,uint256)', eth, usd, '0', MAX)
check(call(pool, 'getUserBorrowBalance(bytes32,address)(uint256)', usd, SENDER) == 0, 'Debt remains after repayment')
for reserve in (eth, usd):
    amount = call(pool, 'getUserDepositBalance(bytes32,address)(uint256)', reserve, SENDER)
    send(pool, 'withdraw(bytes32,uint256)', reserve, str(amount))
    check(call(pool, 'getUserDepositBalance(bytes32,address)(uint256)', reserve, SENDER) == 0, 'Deposit remains after withdrawal')
print('Anvil broadcast lifecycle passed: deposit, borrow, idle accrual, MAX repay, complete withdrawals; debt/deposits zero.')
