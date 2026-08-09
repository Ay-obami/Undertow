// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {FtsoOracle} from "../../src/oracle/FtsoOracle.sol";
import {MockFtsoV2} from "../mocks/MockFtsoV2.sol";

/// @notice Unit tests for FtsoOracle.
///
///         FtsoOracle talks to Flare's ContractRegistry at a fixed, well-known
///         address (0xaD67FE...) that only has bytecode on real Flare networks.
///         In a plain Foundry unit test that address is empty, so instead of
///         forking Coston2 we intercept the one external call FtsoOracle makes
///         through it — `getContractAddressByHash(keccak256("FtsoV2"))` — with
///         `vm.mockCall` and point it at a local `MockFtsoV2`. This mirrors the
///         pattern Flare's own Foundry docs use for testing FTSOv2 consumers.
contract FtsoOracleTest is Test {
    address internal constant REGISTRY = 0xaD67FE66660Fb8dFE9d6b1b4240d8650e30F6019;

    FtsoOracle internal oracle;
    MockFtsoV2 internal mockFtso;

    address internal owner = address(this);
    address internal fxrpFeedKey = address(0xF00D);
    bytes21 internal constant XRP_USD_ID = bytes21(0x015852502f55534400000000000000000000000000); // "XRP/USD"

    uint256 internal constant STALE_PERIOD = 300; // 5 minutes

    function setUp() public {
        oracle = new FtsoOracle(STALE_PERIOD, owner);
        mockFtso = new MockFtsoV2();

        // Any call to the registry's getContractAddressByHash(keccak256("FtsoV2"))
        // returns our mock FTSOv2 contract, regardless of which selector variant
        // (getFtsoV2 / getTestFtsoV2) triggered it — both hash to "FtsoV2".
        vm.mockCall(
            REGISTRY,
            abi.encodeWithSignature("getContractAddressByHash(bytes32)", keccak256(abi.encode("FtsoV2"))),
            abi.encode(address(mockFtso))
        );
    }

    // ── setFeedId ────────────────────────────────────────────────

    function test_SetFeedId_StoresMapping() public {
        oracle.setFeedId(fxrpFeedKey, XRP_USD_ID);
        assertEq(oracle.feedIdOf(fxrpFeedKey), XRP_USD_ID);
    }

    function test_SetFeedId_RevertsIfNotOwner() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert("FtsoOracle: not owner");
        oracle.setFeedId(fxrpFeedKey, XRP_USD_ID);
    }

    function test_SetFeedId_RevertsOnZeroFeedKey() public {
        vm.expectRevert("FtsoOracle: zero feed key");
        oracle.setFeedId(address(0), XRP_USD_ID);
    }

    function test_SetFeedId_RevertsOnZeroFeedId() public {
        vm.expectRevert("FtsoOracle: zero feed id");
        oracle.setFeedId(fxrpFeedKey, bytes21(0));
    }

    // ── getPrice ─────────────────────────────────────────────────

    function test_GetPrice_NormalisesToRay_PositiveDecimals() public {
        oracle.setFeedId(fxrpFeedKey, XRP_USD_ID);
        // XRP/USD = 3.15000 with 5 decimals -> mantissa 315000
        mockFtso.setFeed(XRP_USD_ID, 315000, 5, uint64(block.timestamp));

        uint256 priceRay = oracle.getPrice(fxrpFeedKey);
        assertEq(priceRay, 3.15e18);
    }

    function test_GetPrice_NormalisesToRay_HighDecimals() public {
        oracle.setFeedId(fxrpFeedKey, XRP_USD_ID);
        // decimals > 18: mantissa scaled down
        mockFtso.setFeed(XRP_USD_ID, 3_150_000_000_000_000_000_000, 21, uint64(block.timestamp));

        uint256 priceRay = oracle.getPrice(fxrpFeedKey);
        assertEq(priceRay, 3.15e18);
    }

    function test_GetPrice_RevertsIfFeedNotRegistered() public {
        vm.expectRevert("FtsoOracle: feed not registered");
        oracle.getPrice(fxrpFeedKey);
    }

    function test_GetPrice_RevertsOnNonPositivePrice() public {
        oracle.setFeedId(fxrpFeedKey, XRP_USD_ID);
        mockFtso.setFeed(XRP_USD_ID, 0, 5, uint64(block.timestamp));

        vm.expectRevert("FtsoOracle: non-positive price");
        oracle.getPrice(fxrpFeedKey);
    }

    function test_GetPrice_RevertsOnStalePrice() public {
        oracle.setFeedId(fxrpFeedKey, XRP_USD_ID);
        mockFtso.setFeed(XRP_USD_ID, 315000, 5, uint64(block.timestamp));

        vm.warp(block.timestamp + STALE_PERIOD + 1);

        vm.expectRevert("FtsoOracle: price stale");
        oracle.getPrice(fxrpFeedKey);
    }

    function test_GetPrice_SucceedsAtExactStaleBoundary() public {
        oracle.setFeedId(fxrpFeedKey, XRP_USD_ID);
        mockFtso.setFeed(XRP_USD_ID, 315000, 5, uint64(block.timestamp));

        vm.warp(block.timestamp + STALE_PERIOD);

        uint256 priceRay = oracle.getPrice(fxrpFeedKey);
        assertEq(priceRay, 3.15e18);
    }

    // ── constructor ──────────────────────────────────────────────

    function test_Constructor_RevertsOnZeroStalePeriod() public {
        vm.expectRevert("FtsoOracle: zero stale period");
        new FtsoOracle(0, owner);
    }

    function test_Constructor_RevertsOnZeroOwner() public {
        vm.expectRevert("FtsoOracle: zero owner");
        new FtsoOracle(STALE_PERIOD, address(0));
    }
}
