import { keccak256, toBytes } from 'viem'

/**
 * Matches `Pool.getReserveId(string)` exactly:
 *   function getReserveId(string calldata name) public pure returns (bytes32) {
 *       return keccak256(abi.encodePacked(name));
 *   }
 * For a single `string` argument, `abi.encodePacked(name)` is just the raw
 * UTF-8 bytes of `name` — identical to `keccak256(bytes(name))`, which is
 * what `keccak256(toBytes(name))` computes here.
 *
 * Prefer reading `.id` off data already fetched from the contract
 * (`ReserveInfo.id` / `RawReserveData.id`) over calling this — it exists
 * for the handful of places (e.g. building a UserOp before any reserve data
 * has loaded) where only the name is available client-side.
 */
export function computeReserveId(name: string): `0x${string}` {
  return keccak256(toBytes(name))
}
