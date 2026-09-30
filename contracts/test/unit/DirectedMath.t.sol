// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MathLib} from "../../src/libraries/MathLib.sol";

contract DirectedMathTest is Test {
    function testFuzz_ScalingBoundsEncloseExactValue(uint128 rawAmount, uint96 rawIndex) public {
        uint256 amount = uint256(rawAmount);
        uint256 index = bound(uint256(rawIndex), 1e18, 1e30);
        uint256 down = MathLib.toScaledDown(amount, index);
        uint256 up = MathLib.toScaledUp(amount, index);
        assertLe(down, up);
        assertLe(up - down, 1);
        assertLe(down * index, amount * 1e18);
        assertGe(up * index, amount * 1e18);
    }

    function test_FullPrecisionScalingAvoidsIntermediateOverflow() public {
        assertEq(MathLib.toScaledDown(type(uint256).max, 1e18), type(uint256).max);
        assertEq(MathLib.toScaledUp(type(uint256).max, 1e18), type(uint256).max);
        assertEq(MathLib.mulDivDown(type(uint256).max, type(uint256).max, type(uint256).max), type(uint256).max);
    }

    function test_ZeroIndexRejected() public {
        vm.expectRevert("MathLib: div by zero");
        this.scaleDown(1, 0);
        vm.expectRevert("MathLib: div by zero");
        this.scaleUp(1, 0);
    }

    function scaleDown(uint256 amount, uint256 index) external pure returns (uint256) {
        return MathLib.toScaledDown(amount, index);
    }

    function scaleUp(uint256 amount, uint256 index) external pure returns (uint256) {
        return MathLib.toScaledUp(amount, index);
    }
}
