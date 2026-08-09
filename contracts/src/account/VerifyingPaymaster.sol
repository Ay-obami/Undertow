// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {BasePaymaster} from "@account-abstraction/contracts/core/BasePaymaster.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {_packValidationData} from "@account-abstraction/contracts/core/Helpers.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title VerifyingPaymaster
/// @notice ERC-4337 paymaster that sponsors gas for UserOperations pre-approved
///         by an off-chain `verifyingSigner` — the standard "verifying
///         paymaster" pattern (eth-infinitism's own reference design,
///         adapted here to the v0.9 `PackedUserOperation`/`BasePaymaster`
///         base this repo's `lib/account-abstraction` pins).
///
///         Flow: the protocol's backend decides which calls are eligible for
///         gasless execution (e.g. "deposit and repay are sponsored, borrow
///         is not"), signs `(userOpHash, validUntil, validAfter)` for an
///         approved UserOp, and the frontend appends that signature into
///         `paymasterAndData`. This contract only pays for what a trusted
///         signer already agreed to — it does not sponsor arbitrary calls.
///
///         `paymasterAndData` layout (bytes after the 52-byte header that
///         EntryPoint itself parses — paymaster address + both gas limits):
///           [0:6]    validUntil   (uint48, big-endian)
///           [6:12]   validAfter   (uint48, big-endian)
///           [12:]    signature    (65 bytes, ECDSA)
contract VerifyingPaymaster is BasePaymaster {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /// @notice Off-chain key that approves gasless UserOperations by signature.
    address public verifyingSigner;

    event VerifyingSignerUpdated(address indexed oldSigner, address indexed newSigner);

    constructor(IEntryPoint _entryPoint, address _owner, address _verifyingSigner)
        BasePaymaster(_entryPoint, _owner)
    {
        require(_verifyingSigner != address(0), "VerifyingPaymaster: zero signer");
        verifyingSigner = _verifyingSigner;
    }

    function setVerifyingSigner(address newSigner) external onlyOwner {
        require(newSigner != address(0), "VerifyingPaymaster: zero signer");
        emit VerifyingSignerUpdated(verifyingSigner, newSigner);
        verifyingSigner = newSigner;
    }

    /// @notice The exact hash `verifyingSigner` must sign off-chain to approve
    ///         gas sponsorship for a given UserOp and validity window.
    /// @dev    Deliberately excludes `userOp.signature` (the account's own
    ///         signature) and the trailing paymaster signature itself from
    ///         the hashed data — both change independently of what the
    ///         paymaster is actually approving (that a specific sender may
    ///         run specific callData, sponsored, within a time window).
    function getHash(
        PackedUserOperation calldata userOp,
        uint48 validUntil,
        uint48 validAfter
    ) public view returns (bytes32) {
        return keccak256(
            abi.encode(
                userOp.sender,
                userOp.nonce,
                keccak256(userOp.initCode),
                keccak256(userOp.callData),
                userOp.accountGasLimits,
                uint256(bytes32(userOp.paymasterAndData[PAYMASTER_DATA_OFFSET - 32:PAYMASTER_DATA_OFFSET])), // paymaster + both gas limits, as packed by EntryPoint
                userOp.preVerificationGas,
                userOp.gasFees,
                address(this),
                block.chainid,
                validUntil,
                validAfter
            )
        );
    }

    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32, /* userOpHash */
        uint256 /* maxCost */
    ) internal view virtual override returns (bytes memory context, uint256 validationData) {
        (uint48 validUntil, uint48 validAfter, bytes calldata signature) = _parsePaymasterData(userOp.paymasterAndData);

        require(signature.length == 65, "VerifyingPaymaster: invalid signature length");

        bytes32 hash = getHash(userOp, validUntil, validAfter).toEthSignedMessageHash();
        bool sigFailed = hash.recover(signature) != verifyingSigner;

        return ("", _packValidationData(sigFailed, validUntil, validAfter));
    }

    function _parsePaymasterData(bytes calldata paymasterAndData)
        internal
        pure
        returns (uint48 validUntil, uint48 validAfter, bytes calldata signature)
    {
        bytes calldata data = paymasterAndData[PAYMASTER_DATA_OFFSET:];
        require(data.length >= 12, "VerifyingPaymaster: paymasterData too short");
        validUntil = uint48(bytes6(data[0:6]));
        validAfter = uint48(bytes6(data[6:12]));
        signature = data[12:];
    }

    // No-op by default — pure gas sponsorship, nothing owed back.
    // FxrpGasPaymaster (see FxrpGasPaymaster.sol) overrides this to charge
    // the sponsored gas cost back to the user in FXRP instead.
}
