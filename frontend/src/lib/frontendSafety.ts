export function bindPositionIds<T>(positions: T[], ids: bigint[]): Array<{ position: T; id: number }> {
  if (positions.length !== ids.length) throw new Error('Position IDs changed; refresh before transacting')
  return positions.map((position, index) => {
    const id = Number(ids[index])
    if (!Number.isSafeInteger(id) || id < 0) throw new Error('Unsupported position ID')
    return { position, id }
  })
}

export function parseTokenAmount(value: string, decimals: number): bigint {
  if (!Number.isInteger(decimals) || decimals < 0 || decimals > 18) throw new Error('Unsupported token decimals')
  if (!/^\d+(\.\d+)?$/.test(value)) throw new Error('Enter a positive decimal amount')
  const [whole, fraction = ''] = value.split('.')
  if (fraction.length > decimals) throw new Error(`Amount supports at most ${decimals} decimal places`)
  const amount = BigInt(whole) * 10n ** BigInt(decimals) + BigInt(fraction.padEnd(decimals, '0') || '0')
  if (amount <= 0n) throw new Error('Amount must be positive')
  return amount
}

export function deploymentReady(address: string, chainId: number): boolean {
  return /^0x[0-9a-fA-F]{40}$/.test(address) && !/^0x0{40}$/.test(address) && Number.isSafeInteger(chainId) && chainId > 0
}

export const MAX_REPAY = (1n << 256n) - 1n
export function repaymentApprovalAmount(amount: bigint, walletBalance: bigint): bigint {
  const required = amount === MAX_REPAY ? walletBalance : amount
  if (required <= 0n || required > walletBalance) throw new Error('Insufficient token balance for repayment')
  return required
}
