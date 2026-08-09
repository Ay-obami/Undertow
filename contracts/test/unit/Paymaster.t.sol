// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {VerifyingPaymaster} from "../../src/account/VerifyingPaymaster.sol";
import {FxrpGasPaymaster} from "../../src/account/FxrpGasPaymaster.sol";
import {MockOracle} from "../mocks/MockOracle.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Tests VerifyingPaymaster and FxrpGasPaymaster against a *real*
///         deployed EntryPoint (v0.9's core/EntryPoint.sol) — validation and
///         postOp calls are simulated exactly as EntryPoint would make them
///         (`vm.prank(address(entryPoint))`), rather than against a mock.
contract PaymasterTest is Test {
    EntryPoint internal entryPoint;
    VerifyingPaymaster internal paymaster;

    uint256 internal signerKey = 0xA11CE;
    address internal signer;
    address internal owner = address(this);
    address internal user = address(0xBEEF);

    uint256 internal constant RAY = 1e18;

    function setUp() public {
        entryPoint = new EntryPoint();
        signer = vm.addr(signerKey);
        paymaster = new VerifyingPaymaster(IEntryPoint(address(entryPoint)), owner, signer);
    }

    // ── Helpers ──────────────────────────────────────────────────────

    function _packHi128Lo128(uint128 hi, uint128 lo) internal pure returns (bytes32) {
        return bytes32((uint256(hi) << 128) | uint256(lo));
    }

    function _buildUserOp(bytes memory paymasterAndData) internal view returns (PackedUserOperation memory) {
        return PackedUserOperation({
            sender: user,
            nonce: 0,
            initCode: "",
            callData: hex"1234",
            accountGasLimits: _packHi128Lo128(100_000, 100_000),
            preVerificationGas: 21_000,
            gasFees: _packHi128Lo128(1 gwei, 10 gwei),
            paymasterAndData: paymasterAndData,
            signature: ""
        });
    }

    /// @dev Builds a fully-signed paymasterAndData for `paymaster`, i.e. the
    ///      52-byte EntryPoint-parsed header (paymaster addr + both gas
    ///      limits) followed by (validUntil, validAfter, signature).
    function _signedPaymasterAndData(
        address pm,
        uint256 signerPk,
        uint48 validUntil,
        uint48 validAfter
    ) internal view returns (bytes memory) {
        // Header only, to compute the hash the same way the contract does.
        bytes memory header = abi.encodePacked(pm, uint128(200_000), uint128(50_000));
        PackedUserOperation memory unsigned = _buildUserOp(header);

        bytes32 digest = VerifyingPaymaster(pm).getHash(unsigned, validUntil, validAfter);
        bytes32 ethSigned = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, ethSigned);
        bytes memory sig = abi.encodePacked(r, s, v);

        return abi.encodePacked(header, validUntil, validAfter, sig);
    }


    // ================================================================
    // VerifyingPaymaster
    // ================================================================

    function test_ValidatesAndAccepts_CorrectlySignedUserOp() public {
        uint48 validUntil = uint48(block.timestamp + 1 hours);
        uint48 validAfter = 0;
        bytes memory paymasterAndData = _signedPaymasterAndData(address(paymaster), signerKey, validUntil, validAfter);

        PackedUserOperation memory op = _buildUserOp(paymasterAndData);

        vm.prank(address(entryPoint));
        (, uint256 validationData) = paymaster.validatePaymasterUserOp(op, bytes32(0), 1e15);

        // sigFailed bit (lowest 160 bits interpreted as address) must be 0.
        assertEq(uint160(validationData), 0, "signature should validate");
    }

    function test_Rejects_WrongSigner() public {
        uint256 wrongKey = 0xBAD;
        uint48 validUntil = uint48(block.timestamp + 1 hours);
        bytes memory paymasterAndData = _signedPaymasterAndData(address(paymaster), wrongKey, validUntil, 0);

        PackedUserOperation memory op = _buildUserOp(paymasterAndData);

        vm.prank(address(entryPoint));
        (, uint256 validationData) = paymaster.validatePaymasterUserOp(op, bytes32(0), 1e15);

        assertEq(uint160(validationData), 1, "signature from wrong key must fail validation");
    }

    function test_Rejects_TamperedCallData() public {
        // Sign for one callData, then submit a UserOp with different
        // callData — the signature must no longer match the recomputed hash.
        uint48 validUntil = uint48(block.timestamp + 1 hours);
        bytes memory paymasterAndData = _signedPaymasterAndData(address(paymaster), signerKey, validUntil, 0);

        PackedUserOperation memory op = _buildUserOp(paymasterAndData);
        op.callData = hex"deadbeef"; // tampered after signing

        vm.prank(address(entryPoint));
        (, uint256 validationData) = paymaster.validatePaymasterUserOp(op, bytes32(0), 1e15);

        assertEq(uint160(validationData), 1, "tampered callData must fail validation");
    }

    function test_RevertsIfNotCalledByEntryPoint() public {
        uint48 validUntil = uint48(block.timestamp + 1 hours);
        bytes memory paymasterAndData = _signedPaymasterAndData(address(paymaster), signerKey, validUntil, 0);
        PackedUserOperation memory op = _buildUserOp(paymasterAndData);

        vm.expectRevert();
        paymaster.validatePaymasterUserOp(op, bytes32(0), 1e15);
    }

    function test_SetVerifyingSigner_OnlyOwner() public {
        address newSigner = address(0xCAFE);
        paymaster.setVerifyingSigner(newSigner);
        assertEq(paymaster.verifyingSigner(), newSigner);
    }

    function test_SetVerifyingSigner_RevertsIfNotOwner() public {
        vm.prank(address(0xBAD));
        vm.expectRevert();
        paymaster.setVerifyingSigner(address(0xCAFE));
    }
}

/// @notice Separate contract so its own setUp doesn't collide with
///         PaymasterTest's plain VerifyingPaymaster fixture.
contract FxrpGasPaymasterTest is Test {
    EntryPoint internal entryPoint;
    FxrpGasPaymaster internal paymaster;
    MockOracle internal oracle;
    MockERC20 internal fxrp;

    uint256 internal signerKey = 0xA11CE;
    address internal signer;
    address internal owner = address(this);
    address internal user = address(0xBEEF);
    address internal feeCollector = address(0xC011);

    address internal nativeFeedKey = address(0x1); // WFLR "feed key" placeholder
    address internal fxrpFeedKey = address(0x2);

    uint256 internal constant RAY = 1e18;

    function setUp() public {
        entryPoint = new EntryPoint();
        signer = vm.addr(signerKey);
        oracle = new MockOracle();
        fxrp = new MockERC20("FXRP", "FXRP");

        // FLR/USD = $0.03, XRP/USD (FXRP's price) = $3.15 — realistic-ish ratio.
        oracle.setPrice(nativeFeedKey, 3 * RAY / 100);
        oracle.setPrice(fxrpFeedKey, 315 * RAY / 100);

        paymaster = new FxrpGasPaymaster(
            IEntryPoint(address(entryPoint)),
            owner,
            signer,
            oracle,
            IERC20(address(fxrp)),
            18, // fxrpDecimals — MockERC20 behaves like an 18-decimal token
            nativeFeedKey,
            fxrpFeedKey,
            feeCollector
        );

        fxrp.mint(user, 1_000e18);
        vm.prank(user);
        fxrp.approve(address(paymaster), type(uint256).max);
    }

    function test_QuoteFxrpForGas_MatchesManualCalculation() public view {
        // 1 native token spent on gas (1e18 wei) at $0.03 = $0.03 of gas.
        // FXRP at $3.15 → 0.03/3.15 = 0.0095238... FXRP, plus 10% default buffer.
        uint256 actualGasCostWei = 1e18;
        uint256 quoted = paymaster.quoteFxrpForGas(actualGasCostWei);

        uint256 expectedBase = (actualGasCostWei * (3 * RAY / 100)) / RAY; // USD-RAY value of gas
        expectedBase = (expectedBase * 1e18) / (315 * RAY / 100);          // in FXRP (18-dec)
        uint256 expected = expectedBase + (expectedBase * 1_000) / 10_000; // +10% buffer

        assertEq(quoted, expected);
    }

    function test_PostOp_ChargesFxrpToFeeCollector() public {
        uint256 actualGasCost = 0.01e18; // 0.01 native token spent
        uint256 expectedFxrp = paymaster.quoteFxrpForGas(actualGasCost);
        assertGt(expectedFxrp, 0);

        bytes memory context = abi.encode(user);

        uint256 userBalBefore = fxrp.balanceOf(user);
        uint256 collectorBalBefore = fxrp.balanceOf(feeCollector);

        vm.prank(address(entryPoint));
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, actualGasCost, 1 gwei);

        assertEq(fxrp.balanceOf(user), userBalBefore - expectedFxrp);
        assertEq(fxrp.balanceOf(feeCollector), collectorBalBefore + expectedFxrp);
    }

    function test_PostOp_ChargesEvenOnRevertedUserOp() public {
        // The paymaster already paid real native gas to EntryPoint regardless
        // of whether the sponsored operation itself succeeded — opReverted
        // must still bill the user.
        uint256 actualGasCost = 0.01e18;
        bytes memory context = abi.encode(user);

        uint256 userBalBefore = fxrp.balanceOf(user);

        vm.prank(address(entryPoint));
        paymaster.postOp(IPaymaster.PostOpMode.opReverted, context, actualGasCost, 1 gwei);

        assertLt(fxrp.balanceOf(user), userBalBefore, "user must still be charged on opReverted");
    }

    function test_PostOp_RevertsIfInsufficientAllowance() public {
        vm.prank(user);
        fxrp.approve(address(paymaster), 0); // revoke

        bytes memory context = abi.encode(user);

        vm.prank(address(entryPoint));
        vm.expectRevert();
        paymaster.postOp(IPaymaster.PostOpMode.opSucceeded, context, 0.01e18, 1 gwei);
    }

    function test_SetFeeBufferBps_RevertsAboveCap() public {
        vm.expectRevert("FxrpGasPaymaster: buffer too high");
        paymaster.setFeeBufferBps(5_001);
    }

    function test_SetFeeBufferBps_UpdatesQuote() public {
        uint256 quoteBefore = paymaster.quoteFxrpForGas(1e18);

        paymaster.setFeeBufferBps(0); // no buffer
        uint256 quoteAfter = paymaster.quoteFxrpForGas(1e18);

        assertLt(quoteAfter, quoteBefore, "removing the buffer should lower the quote");
    }

    function test_Constructor_RevertsOnZeroFeeCollector() public {
        vm.expectRevert("FxrpGasPaymaster: zero fee collector");
        new FxrpGasPaymaster(
            IEntryPoint(address(entryPoint)), owner, signer, oracle, IERC20(address(fxrp)), 18, nativeFeedKey, fxrpFeedKey, address(0)
        );
    }
}
