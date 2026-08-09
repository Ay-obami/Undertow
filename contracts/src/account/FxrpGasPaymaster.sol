// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {VerifyingPaymaster} from "./VerifyingPaymaster.sol";
import {IPaymaster} from "@account-abstraction/contracts/interfaces/IPaymaster.sol";
import {PackedUserOperation} from "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title FxrpGasPaymaster
/// @notice VerifyingPaymaster that still pays the EntryPoint in native gas
///         token up front, but recoups that cost from the sponsored user in
///         FXRP afterwards — the "option to pay gas in FXRP" from the PRD.
///
///         Pricing uses the same FtsoOracle already wired up for the Pool
///         (see src/oracle/FtsoOracle.sol): native-gas-token/USD and
///         FXRP/USD (via the XRP/USD feed FXRP is priced off), converting
///         the actual native gas spent into an equivalent FXRP amount, plus
///         a configurable buffer to cover price movement between
///         validation and settlement.
///
///         Requires the sponsored account to have approved this contract to
///         pull FXRP beforehand — typically done in the same batched
///         UserOperation `callData` (approve + the actual deposit/repay
///         call), so the user only ever signs one operation.
contract FxrpGasPaymaster is VerifyingPaymaster {
    using SafeERC20 for IERC20;

    IPriceOracle public immutable oracle;
    IERC20 public immutable fxrp;
    uint8 public immutable fxrpDecimals;

    /// @dev Feed keys as registered in `oracle` (see FtsoOracle.setFeedId) —
    ///      not necessarily the tokens' own addresses; whatever key the
    ///      oracle was configured with for each price.
    address public immutable nativeFeedKey;
    address public immutable fxrpFeedKey;

    /// @notice Extra margin charged over the raw USD-equivalent gas cost,
    ///         in basis points, to absorb price movement between UserOp
    ///         validation and settlement. Default 10%.
    uint256 public feeBufferBps = 1_000;
    uint256 public constant MAX_FEE_BUFFER_BPS = 5_000; // 50% hard cap

    address public feeCollector;

    event GasChargedInFxrp(address indexed sender, uint256 actualGasCostWei, uint256 fxrpCharged);
    event FeeBufferUpdated(uint256 oldBps, uint256 newBps);
    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);

    constructor(
        IEntryPoint _entryPoint,
        address _owner,
        address _verifyingSigner,
        IPriceOracle _oracle,
        IERC20 _fxrp,
        uint8 _fxrpDecimals,
        address _nativeFeedKey,
        address _fxrpFeedKey,
        address _feeCollector
    ) VerifyingPaymaster(_entryPoint, _owner, _verifyingSigner) {
        require(address(_oracle) != address(0), "FxrpGasPaymaster: zero oracle");
        require(address(_fxrp) != address(0), "FxrpGasPaymaster: zero fxrp");
        require(_nativeFeedKey != address(0) && _fxrpFeedKey != address(0), "FxrpGasPaymaster: zero feed key");
        require(_feeCollector != address(0), "FxrpGasPaymaster: zero fee collector");

        oracle = _oracle;
        fxrp = _fxrp;
        fxrpDecimals = _fxrpDecimals;
        nativeFeedKey = _nativeFeedKey;
        fxrpFeedKey = _fxrpFeedKey;
        feeCollector = _feeCollector;
    }

    function setFeeBufferBps(uint256 bps) external onlyOwner {
        require(bps <= MAX_FEE_BUFFER_BPS, "FxrpGasPaymaster: buffer too high");
        emit FeeBufferUpdated(feeBufferBps, bps);
        feeBufferBps = bps;
    }

    function setFeeCollector(address newCollector) external onlyOwner {
        require(newCollector != address(0), "FxrpGasPaymaster: zero fee collector");
        emit FeeCollectorUpdated(feeCollector, newCollector);
        feeCollector = newCollector;
    }

    /// @notice Quotes the FXRP amount owed for a given amount of native gas
    ///         spent, including the fee buffer. Public so a frontend can
    ///         show the user an estimate before they approve.
    function quoteFxrpForGas(uint256 actualGasCostWei) public view returns (uint256) {
        uint256 nativePriceRay = oracle.getPrice(nativeFeedKey); // RAY-scaled USD per 1 native token
        uint256 fxrpPriceRay = oracle.getPrice(fxrpFeedKey);     // RAY-scaled USD per 1 FXRP

        // actualGasCostWei is in 18-decimal native token units.
        uint256 gasCostUsdRay = (actualGasCostWei * nativePriceRay) / 1e18;
        uint256 fxrpAmount = (gasCostUsdRay * (10 ** fxrpDecimals)) / fxrpPriceRay;

        return fxrpAmount + (fxrpAmount * feeBufferBps) / 10_000;
    }

    /// @dev Runs the normal signature check, then carries the sponsored
    ///      account's address through to `_postOp` so it knows who to bill.
    function _validatePaymasterUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) internal view override returns (bytes memory context, uint256 validationData) {
        (, validationData) = super._validatePaymasterUserOp(userOp, userOpHash, maxCost);
        context = abi.encode(userOp.sender);
    }

    function _postOp(
        IPaymaster.PostOpMode, /* mode */
        bytes calldata context,
        uint256 actualGasCost,
        uint256 /* actualUserOpFeePerGas */
    ) internal override {
        address sender = abi.decode(context, (address));

        uint256 fxrpOwed = quoteFxrpForGas(actualGasCost);
        if (fxrpOwed == 0) return;

        // Charged even if the UserOp itself reverted (opReverted) — the
        // paymaster still paid real gas to the EntryPoint either way. If the
        // sender hasn't approved enough FXRP, this reverts and the
        // paymaster eats the cost for this one operation, exactly like
        // running out of a pre-funded balance would.
        fxrp.safeTransferFrom(sender, feeCollector, fxrpOwed);

        emit GasChargedInFxrp(sender, actualGasCost, fxrpOwed);
    }
}
