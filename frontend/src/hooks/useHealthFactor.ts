import { useReadContract } from 'wagmi'
import { POOL_ABI } from '../lib/abi'
import { POOL_ADDRESS, POOL_CHAIN_ID, POOL_CONFIGURED } from '../lib/wagmi'

// The contract previews accrued debt and values both assets using its oracle.
// checkPositionHealth returns a boolean; it does not expose a numeric ratio.
export function useHealthFactor(user: `0x${string}` | undefined, positionId: number, enabled = false) {
  const query = useReadContract({
    chainId: POOL_CHAIN_ID,
    address: POOL_ADDRESS,
    abi: POOL_ABI,
    functionName: 'checkPositionHealth',
    args: user ? [user, BigInt(positionId)] : undefined,
    query: { enabled: POOL_CONFIGURED && !!user && enabled, staleTime: 15_000 },
  })
  return { data: query.data, isLoading: query.isLoading, error: query.error }
}
