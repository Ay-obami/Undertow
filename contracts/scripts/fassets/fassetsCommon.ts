// Minimal ABI fragments + registry helpers shared by the FAssets mint scripts.
// Deliberately hand-trimmed to only what these scripts call, so we don't need
// the full IAssetManager artifact/typechain output — just ethers + plain ABI.

import { AbiCoder, Contract, JsonRpcProvider, Wallet, keccak256 } from "ethers";

export const FLARE_CONTRACT_REGISTRY_ADDRESS =
  "0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019"; // same address on every Flare network

const REGISTRY_ABI = [
  "function getContractAddressByHash(bytes32 nameHash) view returns (address)",
];

export const ASSET_MANAGER_ABI = [
  "function fAsset() view returns (address)",
  "function assetMintingDecimals() view returns (uint8)",
  "function getAvailableAgentsDetailedList(uint256 start, uint256 end) view returns (tuple(address agentVault, uint256 feeBIPS, uint256 mintingClass1CollateralRatioBIPS, uint256 mintingPoolCollateralRatioBIPS, uint256 freeCollateralLots, string status)[] agents, uint256 totalLength)",
  "function getAgentInfo(address agentVault) view returns (tuple(uint8 status, address ownerManagementAddress, string underlyingAddressString, uint256 publiclyAvailable, uint256 feeBIPS, uint256 mintingClass1CollateralRatioBIPS, uint256 mintingPoolCollateralRatioBIPS, uint256 freeCollateralLots) info)",
  "function collateralReservationFee(uint256 lots) view returns (uint256)",
  "function reserveCollateral(address agentVault, uint256 lots, uint256 maxMintingFeeBIPS, address payable executor) payable returns (uint256 collateralReservationId)",
  "function collateralReservationInfo(uint256 collateralReservationId) view returns (tuple(address minter, address agentVault, uint256 valueUBA, uint256 feeUBA, uint256 firstUnderlyingBlock, uint256 lastUnderlyingBlock, uint256 lastUnderlyingTimestamp, string paymentAddress, bytes32 paymentReference, address executor, uint256 executorFeeNatWei) info)",
  "function executeMinting(tuple(bytes32[] merkleProof, tuple(bytes32 attestationType, bytes32 sourceId, uint64 votingRound, uint64 lowestUsedTimestamp, tuple(bytes32 transactionId, uint256 inUtxo, uint256 utxo, string sourceAddressHash, string sourceAddressesRoot, string receivingAddressHash, int256 spentAmount, int256 receivedAmount, uint256 standardPaymentReference, bool oneToOne, string status) requestBody) proof) collateralReservationId) external",
  "event CollateralReserved(address indexed agentVault, address indexed minter, uint256 collateralReservationId, uint256 valueUBA, uint256 feeUBA, uint256 firstUnderlyingBlock, uint256 lastUnderlyingBlock, uint256 lastUnderlyingTimestamp, string paymentAddress, bytes32 paymentReference, address executor, uint256 executorFeeNatWei)",
];

/**
 * Look up the FXRP AssetManager address via the Flare Contract Registry.
 * Registry address + lookup pattern is identical across all Flare networks;
 * only the *result* (the AssetManager address) differs between them.
 */
export async function getAssetManagerFXRP(
  provider: JsonRpcProvider,
  signerOrProvider: Wallet | JsonRpcProvider = provider
) {
  const registry = new Contract(FLARE_CONTRACT_REGISTRY_ADDRESS, REGISTRY_ABI, provider);
  const nameHash = ethersKeccakOfName("AssetManagerFXRP");
  const address: string = await registry.getContractAddressByHash(nameHash);
  if (address === "0x0000000000000000000000000000000000000000") {
    throw new Error("AssetManagerFXRP not found in registry on this network");
  }
  return new Contract(address, ASSET_MANAGER_ABI, signerOrProvider);
}

// keccak256(abi.encode(string)) — matches ContractRegistry.sol's
// `keccak256(abi.encode("AssetManagerFXRP"))` name-hash convention exactly.
function ethersKeccakOfName(name: string): string {
  // abi.encode(string) is NOT the same as utf8-encoding the raw string —
  // it's the standard ABI encoding of a single `string` parameter.
  // ethers' AbiCoder replicates this precisely.
  const encoded = AbiCoder.defaultAbiCoder().encode(["string"], [name]);
  return keccak256(encoded);
}
