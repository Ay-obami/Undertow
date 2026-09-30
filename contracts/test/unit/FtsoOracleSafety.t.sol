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
contract FtsoOracleSafetyTest is Test {
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

    function test_RejectsZeroTimestampEvenWithinStalePeriod() public {
        vm.warp(100);
        oracle.setFeedId(fxrpFeedKey, XRP_USD_ID);
        mockFtso.setFeed(XRP_USD_ID, 315000, 5, 0);
        vm.expectRevert("FtsoOracle: round not complete");
        oracle.getPrice(fxrpFeedKey);
    }

    function test_RejectsPriceThatNormalisesToZero() public {
        oracle.setFeedId(fxrpFeedKey, XRP_USD_ID);
        mockFtso.setFeed(XRP_USD_ID, 1, 19, uint64(block.timestamp));
        vm.expectRevert("FtsoOracle: price below precision");
        oracle.getPrice(fxrpFeedKey);
    }

    function test_RejectsFutureTimestampExplicitly() public {
        oracle.setFeedId(fxrpFeedKey, XRP_USD_ID);
        mockFtso.setFeed(XRP_USD_ID, 315000, 5, uint64(block.timestamp + 1));
        vm.expectRevert("FtsoOracle: future timestamp");
        oracle.getPrice(fxrpFeedKey);
    }

    function test_RejectsUnsupportedExponentExplicitly() public {
        oracle.setFeedId(fxrpFeedKey, XRP_USD_ID);
        mockFtso.setFeed(XRP_USD_ID, 1, 96, uint64(block.timestamp));
        vm.expectRevert("FtsoOracle: unsupported decimals");
        oracle.getPrice(fxrpFeedKey);
    }
}
