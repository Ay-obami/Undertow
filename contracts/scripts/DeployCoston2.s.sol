// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Pool} from "../src/modules/Pool.sol";
import {FtsoOracle} from "../src/oracle/FtsoOracle.sol";
import {VariableInterestStrategy} from "../src/modules/VariableInterestStrategy.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";
import {ContractRegistry} from "@flarenetwork/flare-periphery-contracts/coston2/ContractRegistry.sol";

/// @title DeployCoston2
/// @notice Week 2 deploy script — stands the protocol up on Flare Testnet
///         Coston2 with FXRP as a first-class reserve, priced via FTSOv2.
///
///         Usage:
///           forge script scripts/DeployCoston2.s.sol --rpc-url coston2 --broadcast
///
///         Prerequisites:
///           - RPC configured for Coston2 (see foundry.toml [rpc_endpoints])
///           - Deployer funded with testnet C2FLR (https://faucet.flare.network/coston2)
///           - For FXRP itself: testnet FXRP is available directly from the
///             Coston2 faucet — no minting required to just try the pool.
///             (See scripts/fassets/README.md for the full mint-from-XRP flow,
///             which is what a real user would do post-hackathon / on mainnet.)
contract DeployCoston2 is Script {
    uint256 constant RAY = 1e18;

    // FTSOv2 feed ids — see https://dev.flare.network/ftso/feeds
    // Category 1 ("crypto") + symbol, ASCII, right-padded with zero bytes to 21 bytes total.
    bytes21 constant XRP_USD_FEED_ID = bytes21(0x015852502f55534400000000000000000000000000);
    bytes21 constant FLR_USD_FEED_ID = bytes21(0x01464c522f55534400000000000000000000000000);

    uint256 constant ORACLE_STALE_PERIOD = 90; // seconds — FTSOv2 block-latency feeds update ~every block

    function run() external {
        vm.startBroadcast();
        // IMPORTANT: `deployer` must be read *after* startBroadcast(), not
        // before. Pre-broadcast, `msg.sender` inside a forge script is
        // Foundry's internal default sender (0x1804c8AB...), not the actual
        // account whose key will sign the broadcast transactions. Since
        // `deployer` becomes FtsoOracle's immutable owner below, getting
        // this backwards would permanently lock oracle administration
        // (setFeedId etc.) to an address nobody holds the key for.
        address deployer = msg.sender;

        // ── 1. Shared infrastructure ─────────────────────────────────
        VariableInterestStrategy strategy = new VariableInterestStrategy();
        FtsoOracle oracle = new FtsoOracle(ORACLE_STALE_PERIOD, deployer);

        // ── 2. Resolve real Coston2 asset addresses via the Flare registry ──
        // FXRP: the FAsset ERC20 minted by the FXRP AssetManager.
        address fxrpAddr = address(ContractRegistry.getAssetManagerFXRP().fAsset());
        require(fxrpAddr != address(0), "DeployCoston2: FXRP not found in registry");

        // WFLR: wrapped native FLR, used as a second collateral/borrow asset
        // alongside FXRP (per PRD: "1-2 existing supported tokens").
        address wflrAddr = address(ContractRegistry.getWNat());
        require(wflrAddr != address(0), "DeployCoston2: WNat not found in registry");

        // ── 3. Register FTSOv2 feed ids ──────────────────────────────
        // feedKey convention: the reserve's own token address (see FtsoOracle docs).
        oracle.setFeedId(fxrpAddr, XRP_USD_FEED_ID); // FXRP is 1:1 backed by XRP — price off XRP/USD
        oracle.setFeedId(wflrAddr, FLR_USD_FEED_ID);

        // ── 4. Deploy Pool ────────────────────────────────────────────
        Pool pool = new Pool(address(oracle));

        // ── 5. Register reserves ─────────────────────────────────────
        pool.addReserve(DataTypes.ReserveConfig({
            name:                 "FXRP",
            tokenAddress:         fxrpAddr,
            priceFeed:            fxrpAddr, // feed key == token address, see FtsoOracle
            interestStrategy:     address(strategy),
            liquidationThreshold: 80 * RAY / 100,
            ltv:                  75 * RAY / 100,
            slope1:               5  * RAY / 100,
            slope2:               75 * RAY / 100,
            baseInterestRate:     1  * RAY / 100,
            optimalUtilization:   75 * RAY / 100,
            liquidationBonus:     8  * RAY / 100,
            reserveFactor:        15 * RAY / 100,
            borrowCap:            500_000e6,  // FXRP mirrors XRPL's 6-decimal precision
            supplyCap:            500_000e6,
            isActive:             true,
            isBorrowable:         true
        }));

        pool.addReserve(DataTypes.ReserveConfig({
            name:                 "WFLR",
            tokenAddress:         wflrAddr,
            priceFeed:            wflrAddr,
            interestStrategy:     address(strategy),
            liquidationThreshold: 70 * RAY / 100,
            ltv:                  65 * RAY / 100,
            slope1:               6  * RAY / 100,
            slope2:               90 * RAY / 100,
            baseInterestRate:     2  * RAY / 100,
            optimalUtilization:   70 * RAY / 100,
            liquidationBonus:     10 * RAY / 100,
            reserveFactor:        20 * RAY / 100,
            borrowCap:            5_000_000e18,
            supplyCap:            5_000_000e18,
            isActive:             true,
            isBorrowable:         true
        }));

        vm.stopBroadcast();

        // ── 6. Log addresses ─────────────────────────────────────────
        console.log("Pool deployed at:      ", address(pool));
        console.log("FtsoOracle deployed at:", address(oracle));
        console.log("Strategy deployed at:  ", address(strategy));
        console.log("FXRP token address:    ", fxrpAddr);
        console.log("WFLR token address:    ", wflrAddr);
        console.log("");
        console.log("Get testnet FXRP + C2FLR: https://faucet.flare.network/coston2");
    }
}
