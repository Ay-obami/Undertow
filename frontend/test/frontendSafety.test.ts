import assert from 'node:assert/strict'
import { test } from 'node:test'
import { bindPositionIds, parseTokenAmount, deploymentReady, repaymentApprovalAmount, MAX_REPAY } from '../src/lib/frontendSafety.ts'

test('repay and health retain original IDs after the first position closes', () => {
  assert.deepEqual(bindPositionIds(['second', 'fourth'], [1n, 3n]), [{ position: 'second', id: 1 }, { position: 'fourth', id: 3 }])
})
test('mismatched ID reads cannot target a position', () => {
  assert.throws(() => bindPositionIds(['second'], []))
})
test('token amounts preserve bigint precision and honor six decimals', () => {
  assert.equal(parseTokenAmount('9007199254740993.123456', 6), 9007199254740993123456n)
  assert.equal(parseTokenAmount('1', 0), 1n)
  assert.equal(parseTokenAmount('0.000001', 6), 1n)
})
test('excess precision and nonpositive amounts are rejected instead of rounded', () => {
  for (const input of ['0.0000001', '-1', '0', '1e3', 'NaN']) assert.throws(() => parseTokenAmount(input, 6))
})
test('unconfigured and invalid deployments stay disabled', () => {
  assert.equal(deploymentReady('0x0000000000000000000000000000000000000000', 114), false)
  assert.equal(deploymentReady('not-an-address', 114), false)
  assert.equal(deploymentReady('0x1111111111111111111111111111111111111111', 0), false)
  assert.equal(deploymentReady('0x1111111111111111111111111111111111111111', 114), true)
})

test('full repayment requests do not approve an unlimited allowance', () => {
  assert.equal(repaymentApprovalAmount(MAX_REPAY, 200n), 200n)
  assert.equal(repaymentApprovalAmount(100n, 200n), 100n)
})
test('repayment is rejected when the wallet cannot cover the requested allowance', () => {
  assert.throws(() => repaymentApprovalAmount(201n, 200n))
  assert.throws(() => repaymentApprovalAmount(MAX_REPAY, 0n))
})
