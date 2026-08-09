import { useState } from 'react'
import { useAccount } from 'wagmi'
import { parseUnits } from 'viem'
import { useReserves } from '../../hooks/useReserves'
import { useContract } from '../../hooks/useContract'
import { TxStatusBar, Skeleton } from '../common'
import { formatNumber, formatPercent, RAY } from '../../lib/math'

const MIN_BUFFER = 0.05   // 5%
const DEFAULT_BUFFER = 0.1 // 10%

export function BorrowForm({ onSuccess }: { onSuccess?: () => void }) {
  const { address } = useAccount()
  const { data: reserves, isLoading } = useReserves()
  const { borrow, txState, resetTxState } = useContract()

  const [step, setStep] = useState<1 | 2>(1)
  const [collateral, setCollateral] = useState('')
  const [borrowAsset, setBorrowAsset] = useState('')
  const [amount, setAmount] = useState('')
  const [bufferPct, setBufferPct] = useState(DEFAULT_BUFFER)
  const [isBusy, setIsBusy] = useState(false)

  const collateralReserve = reserves?.collateral.find((r) => r.name === collateral) ?? null
  const borrowReserve = reserves?.borrowable.find((r) => r.name === borrowAsset) ?? null

  const handleNext = () => {
    if (!collateral) return
    setStep(2)
  }

  const handleBack = () => {
    setStep(1)
    setBorrowAsset('')
    setAmount('')
  }

  const handleBorrow = async () => {
    if (!address || !collateral || !borrowAsset || !amount || Number(amount) <= 0) return
    setIsBusy(true)
    resetTxState()
    try {
      const parsed = parseUnits(amount, 18)
      // bufferPercent is RAY-scaled (1e18 = 100%)
      const bufferRay = BigInt(Math.round(bufferPct * 1e18))
      await borrow(collateral, borrowAsset, parsed, bufferRay)
      setCollateral('')
      setBorrowAsset('')
      setAmount('')
      setStep(1)
      onSuccess?.()
    } catch {
      // error handled in hook
    } finally {
      setIsBusy(false)
    }
  }

  if (isLoading) {
    return (
      <div className="panel p-6 space-y-4">
        <Skeleton className="h-5 w-32 rounded" />
        <Skeleton className="h-10 rounded-lg" />
        <Skeleton className="h-10 rounded-lg" />
        <Skeleton className="h-10 rounded-lg" />
      </div>
    )
  }

  if (!reserves) return null

  return (
    <div className="panel p-6 space-y-6">
      {/* Step indicator */}
      <div className="flex items-center gap-3">
        <StepDot n={1} active={step === 1} done={step === 2} label="Select Collateral" />
        <div className="flex-1 h-px bg-[#2A2A2E]" />
        <StepDot n={2} active={step === 2} done={false} label="Configure Borrow" />
      </div>

      {step === 1 && (
        <div className="space-y-4">
          <div>
            <label className="label mb-2 block">Collateral Asset</label>
            <div className="relative">
              <select
                value={collateral}
                onChange={(e) => setCollateral(e.target.value)}
                className="select-field"
              >
                <option value="" disabled>Select collateral…</option>
                {reserves.collateral.map((r) => (
                  <option key={r.name} value={r.name}>{r.name}</option>
                ))}
              </select>
              <ChevronDown />
            </div>
          </div>

          {collateralReserve && (
            <div className="bg-[#0B0B0C] rounded-lg p-3 space-y-2">
              <InfoRow label="LTV" value={formatPercent(collateralReserve.ltv)} />
              <InfoRow label="Liq. Threshold" value={formatPercent(collateralReserve.liquidationThreshold)} />
              <InfoRow label="Supply APY" value={formatPercent(collateralReserve.supplyAPY)} highlight="green" />
            </div>
          )}

          <button
            onClick={handleNext}
            disabled={!collateral}
            className="btn-primary w-full"
          >
            Continue →
          </button>
        </div>
      )}

      {step === 2 && (
        <div className="space-y-4">
          <div className="flex items-center gap-2 text-sm text-[#A1A1AA]">
            <button onClick={handleBack} className="hover:text-white transition-colors">← Back</button>
            <span className="text-[#2A2A2E]">|</span>
            <span>Collateral: <span className="text-white font-medium">{collateral}</span></span>
          </div>

          {/* Borrow asset */}
          <div>
            <label className="label mb-2 block">Borrow Asset</label>
            <div className="relative">
              <select
                value={borrowAsset}
                onChange={(e) => setBorrowAsset(e.target.value)}
                className="select-field"
              >
                <option value="" disabled>Select asset to borrow…</option>
                {reserves.borrowable
                  .filter((r) => r.name !== collateral)
                  .map((r) => (
                    <option key={r.name} value={r.name}>{r.name}</option>
                  ))}
              </select>
              <ChevronDown />
            </div>
          </div>

          {borrowReserve && (
            <div className="bg-[#0B0B0C] rounded-lg p-3 space-y-2">
              <InfoRow label="Borrow APY" value={formatPercent(borrowReserve.borrowAPY)} highlight="yellow" />
              <InfoRow label="Available Liquidity" value={formatNumber(borrowReserve.totalDeposits - borrowReserve.totalBorrows)} />
              <InfoRow label="Utilization" value={formatPercent(borrowReserve.utilizationRate)} />
            </div>
          )}

          {/* Amount */}
          <div>
            <label className="label mb-2 block">Amount to Borrow</label>
            <input
              type="number"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="0.0"
              className="input-field"
              min="0"
              step="any"
              disabled={isBusy}
            />
          </div>

          {/* Buffer slider */}
          <div>
            <div className="flex justify-between items-center mb-2">
              <label className="label">Collateral Buffer</label>
              <span className="font-mono text-sm text-accent">{formatPercent(bufferPct)}</span>
            </div>
            <input
              type="range"
              min={5}
              max={50}
              step={1}
              value={Math.round(bufferPct * 100)}
              onChange={(e) => setBufferPct(Number(e.target.value) / 100)}
              className="w-full h-1 bg-[#2A2A2E] rounded-full appearance-none cursor-pointer accent-accent"
            />
            <div className="flex justify-between text-xs text-[#6B7280] mt-1">
              <span>5% (min)</span>
              <span>Safer →</span>
              <span>50%</span>
            </div>
            <p className="text-xs text-[#6B7280] mt-1">
              Higher buffer = more collateral locked, lower liquidation risk
            </p>
          </div>

          {txState.status !== 'idle' && <TxStatusBar state={txState} />}

          <button
            onClick={handleBorrow}
            disabled={!borrowAsset || !amount || Number(amount) <= 0 || isBusy || !address}
            className="btn-primary w-full"
          >
            {!address
              ? 'Connect Wallet'
              : isBusy
              ? 'Processing…'
              : 'Borrow'}
          </button>
        </div>
      )}
    </div>
  )
}

function StepDot({ n, active, done, label }: { n: number; active: boolean; done: boolean; label: string }) {
  return (
    <div className="flex flex-col items-center gap-1">
      <div
        className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold transition-all ${
          done ? 'bg-[#22C55E] text-black' : active ? 'bg-accent text-white' : 'bg-[#2A2A2E] text-[#6B7280]'
        }`}
      >
        {done ? '✓' : n}
      </div>
      <span className={`text-xs whitespace-nowrap ${active ? 'text-white' : 'text-[#6B7280]'}`}>{label}</span>
    </div>
  )
}

function InfoRow({ label, value, highlight }: { label: string; value: string; highlight?: 'green' | 'yellow' }) {
  return (
    <div className="flex justify-between items-center">
      <span className="text-xs text-[#6B7280]">{label}</span>
      <span className={`font-mono text-xs font-medium ${
        highlight === 'green' ? 'text-[#22C55E]' : highlight === 'yellow' ? 'text-[#EAB308]' : 'text-[#A1A1AA]'
      }`}>{value}</span>
    </div>
  )
}

function ChevronDown() {
  return (
    <div className="pointer-events-none absolute right-3 top-1/2 -translate-y-1/2">
      <svg className="w-4 h-4 text-[#6B7280]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
        <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
      </svg>
    </div>
  )
}
