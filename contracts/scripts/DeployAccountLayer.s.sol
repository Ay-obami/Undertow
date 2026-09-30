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
/// @notice Experimental account-layer deployment, excluded from supported
///         lending deployments. Creates EntryPoint, factory and paymasters;
///         it does not establish a working handleOps/bundler/frontend flow
///         or guarantee FXRP recovery. Funding defaults to zero.
///
///         Run *after* DeployCoston2.s.sol — needs its FtsoOracle and FXRP
///         addresses.
///
///         Usage:
///           ENABLE_EXPERIMENTAL_ACCOUNT_LAYER=true \
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
        require(
            vm.envOr("ENABLE_EXPERIMENTAL_ACCOUNT_LAYER", false),
            "DeployAccountLayer: experimental account layer disabled"
        );
        uint256 experimentalDeposit = vm.envOr("EXPERIMENTAL_PAYMASTER_DEPOSIT", uint256(0));
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
        // This experiment deploys a fresh EntryPoint. It makes no claim about
        // canonical deployments on Coston2; configure and verify bundler
        // compatibility with this exact EntryPoint before experiments.
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
        // Funding defaults to zero. EXPERIMENTAL_PAYMASTER_DEPOSIT explicitly
        // requests the same native-token deposit for each paymaster.
        // Public sponsorship is outside the supported lending scope.
        // Leave both deposits empty unless explicitly requested for an experiment.
        if (experimentalDeposit > 0) {
            verifyingPaymaster.deposit{value: experimentalDeposit}();
            fxrpPaymaster.deposit{value: experimentalDeposit}();
        }

        vm.stopBroadcast();

        console.log("EntryPoint deployed at:          ", address(entryPoint));
        console.log("SimpleAccountFactory deployed at:", address(accountFactory));
        console.log("VerifyingPaymaster deployed at:  ", address(verifyingPaymaster));
        console.log("FxrpGasPaymaster deployed at:     ", address(fxrpPaymaster));
        console.log("Verifying signer:                ", verifyingSigner);
    }
}
