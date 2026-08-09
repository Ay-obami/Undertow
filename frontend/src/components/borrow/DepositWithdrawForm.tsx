import { useState } from 'react'
import { useAccount } from 'wagmi'
import { parseUnits } from 'viem'
import type { ReserveInfo } from '../../types'
import { useContract } from '../../hooks/useContract'
import { TxStatusBar } from '../common'
import { formatNumber } from '../../lib/math'
import { useConfig } from 'wagmi'
import { fetchTokenBalance } from '../../services/poolService'
import { useQuery } from '@tanstack/react-query'

// ─── Deposit / Withdraw Form ───────────────────────────────────────────────
export function DepositWithdrawForm({
  reserve,
  mode,
  onSuccess,
}: {
  reserve: ReserveInfo
  mode: 'deposit' | 'withdraw'
  onSuccess?: () => void
}) {
  const { address } = useAccount()
  const config = useConfig()
  const [amount, setAmount] = useState('')
  const [isBusy, setIsBusy] = useState(false)
  const { deposit, withdraw, txState, resetTxState } = useContract()

  const { data: walletBalance } = useQuery({
    queryKey: ['tokenBalance', reserve.tokenAddress, address],
    enabled: !!address && mode === 'deposit',
    queryFn: () => fetchTokenBalance(config, reserve.tokenAddress, address!),
    staleTime: 10_000,
  })

  const walletNum = walletBalance ? Number(walletBalance) / 1e18 : 0

  const handleSubmit = async () => {
    if (!address || !amount || Number(amount) <= 0) return
    setIsBusy(true)
    resetTxState()
    try {
      const parsed = parseUnits(amount, 18)
      if (mode === 'deposit') {
        await deposit(reserve.name, parsed, reserve.tokenAddress, address)
      } else {
        await withdraw(reserve.name, parsed)
      }
      setAmount('')
      onSuccess?.()
    } catch {
      // error handled in hook
    } finally {
      setIsBusy(false)
    }
  }

  const setMax = () => {
    if (mode === 'deposit' && walletBalance) {
      setAmount((Number(walletBalance) / 1e18).toFixed(6))
    }
  }

  return (
    <div className="space-y-3">
      <div className="relative">
        <input
          type="number"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          placeholder="0.0"
          className="input-field pr-16"
          min="0"
          step="any"
          disabled={isBusy}
        />
        {mode === 'deposit' && (
          <button
            onClick={setMax}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-xs text-accent hover:text-blue-400 font-medium px-2 py-1 rounded"
          >
            MAX
          </button>
        )}
      </div>

      {mode === 'deposit' && address && (
        <div className="text-xs text-[#6B7280]">
          Wallet balance:{' '}
          <span className="font-mono text-[#A1A1AA]">{formatNumber(walletNum, 4)} {reserve.name}</span>
        </div>
      )}

      {txState.status !== 'idle' && <TxStatusBar state={txState} />}

      <button
        onClick={handleSubmit}
        disabled={!amount || Number(amount) <= 0 || isBusy || !address}
        className="btn-primary w-full"
      >
        {!address
          ? 'Connect Wallet'
          : isBusy
          ? 'Processing…'
          : mode === 'deposit'
          ? `Deposit ${reserve.name}`
          : `Withdraw ${reserve.name}`}
      </button>
    </div>
  )
}
