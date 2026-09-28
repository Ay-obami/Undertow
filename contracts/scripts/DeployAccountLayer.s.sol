// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {SimpleAccountFactory} from "@account-abstraction/contracts/accounts/SimpleAccountFactory.sol";
import {VerifyingPaymaster} from "../src/account/VerifyingPaymaster.sol";
import {FxrpGasPaymaster} from "../src/account/FxrpGasPaymaster.sol";
import {IPriceOracle} from "../src/interfaces/IPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ContractRegistry} from "@flarenetwork/flare-periphery-contracts/coston2/ContractRegistry.sol";

/// @title DeployAccountLayer
/// @notice Week 5 deploy script — stands up the ERC-4337 account layer on
///         Coston2 and wires it to the FXRP/WFLR reserves from
///         DeployCoston2.s.sol, so deposit/repay can be sponsored gaslessly
///         (optionally billed back in FXRP).
///
///         Run *after* DeployCoston2.s.sol — needs its FtsoOracle and FXRP
///         addresses.
///
///         Usage:
///           FTSO_ORACLE=0x... VERIFYING_SIGNER=0x... \
///           forge script scripts/DeployAccountLayer.s.sol --rpc-url coston2 --broadcast
///
///         `VERIFYING_SIGNER` is the off-chain key that will sign approvals
///         for gasless UserOperations (see VerifyingPaymaster.getHash) — set
///         it to a key your backend controls, NOT the deployer key, since
///         the deployer key typically shouldn't also be your live signer.
///         Defaults to the deployer if unset (fine for a demo, not for
///         anything beyond one).
contract DeployAccountLayer is Script {
    function run() external {
        address ftsoOracle = vm.envAddress("FTSO_ORACLE"); // from DeployCoston2.s.sol output — no broadcast dependency, safe to read early

        vm.startBroadcast();
        // IMPORTANT: `deployer` must be read *after* startBroadcast(), not
        // before — see the identical note in DeployCoston2.s.sol. Both
        // paymasters use OpenZeppelin's Ownable2Step, so an owner set to
        // Foundry's pre-broadcast default sender (an address nobody holds
        // the key for) would be a *permanent, unrecoverable* loss of admin
        // control — there'd be no key to call transferOwnership from.
        address deployer = msg.sender;
        address verifyingSigner = vm.envOr("VERIFYING_SIGNER", deployer);

        // ── 1. EntryPoint + account factory ──────────────────────────
        // Coston2 doesn't have a canonical v0.9 EntryPoint pre-deployed
        // (v0.9 is recent), so this deploys a fresh one rather than
        // assuming an address. If your bundler/infra expects the canonical
        // ERC-4337 EntryPoint address instead, point VERIFYING_SIGNER's
        // infra at this deployed address, or swap in the canonical one here.
        EntryPoint entryPoint = new EntryPoint();
        SimpleAccountFactory accountFactory = new SimpleAccountFactory(IEntryPoint(address(entryPoint)));

        // ── 2. Plain verifying paymaster (sponsors gas outright) ─────
        VerifyingPaymaster verifyingPaymaster =
            new VerifyingPaymaster(IEntryPoint(address(entryPoint)), deployer, verifyingSigner);

        // ── 3. FXRP-billed paymaster ──────────────────────────────────
        address fxrpAddr = address(ContractRegistry.getAssetManagerFXRP().fAsset());
        address wflrAddr = address(ContractRegistry.getWNat());

        FxrpGasPaymaster fxrpPaymaster = new FxrpGasPaymaster(
            IEntryPoint(address(entryPoint)),
            deployer,
            verifyingSigner,
            IPriceOracle(ftsoOracle),
            IERC20(fxrpAddr),
            6, // FXRP mirrors XRPL's 6-decimal precision
            wflrAddr, // native-gas-token feed key. Gas on Coston2 is paid in
            // native C2FLR, not the WFLR ERC20 — but WFLR is 1:1
            // wrapped native FLR, so its already-registered FLR/USD
            // feed (from DeployCoston2.s.sol) prices native gas
            // correctly without registering a second, identical feed.
            fxrpAddr, // FXRP feed key — same convention as DeployCoston2.s.sol: feed key == token address
            deployer // fee collector — route FXRP gas payments to the deployer/treasury for now
        );

        // ── 4. Fund both paymasters' EntryPoint deposits ─────────────
        // A paymaster needs a deposit at the EntryPoint to actually sponsor
        // gas — this is separate from the paymaster contract's own balance.
        // Amounts here are a starting point for a demo, not a sizing
        // recommendation; top up via `paymaster.deposit{value: ...}()`.
        verifyingPaymaster.deposit{value: 0.05 ether}();
        fxrpPaymaster.deposit{value: 0.05 ether}();

        vm.stopBroadcast();

        console.log("EntryPoint deployed at:          ", address(entryPoint));
        console.log("SimpleAccountFactory deployed at:", address(accountFactory));
        console.log("VerifyingPaymaster deployed at:  ", address(verifyingPaymaster));
        console.log("FxrpGasPaymaster deployed at:     ", address(fxrpPaymaster));
        console.log("Verifying signer:                ", verifyingSigner);
    }
}
