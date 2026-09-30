// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolTestBase} from "./PoolTestBase.sol";
import {Pool} from "../../src/modules/Pool.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract CallbackReserveToken is ERC20 {
    Pool internal immutable pool;
    bytes internal callbackData;
    bool internal armed;
    bool internal bubbleFailure;
    bool public attempted;
    bool public succeeded;
    bytes public result;

    constructor(Pool pool_) ERC20("Callback dollar", "cUSD") {
        pool = pool_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function arm(bytes memory data, bool bubble) external {
        callbackData = data;
        bubbleFailure = bubble;
        armed = true;
        attempted = false;
        succeeded = false;
        delete result;
    }

    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);
        if (armed && (from == address(pool) || to == address(pool))) {
            armed = false;
            attempted = true;
            (succeeded, result) = address(pool).call(callbackData);
            if (bubbleFailure && !succeeded) {
                bytes memory failure = result;
                assembly {
                    revert(add(failure, 32), mload(failure))
                }
            }
        }
    }
}

contract CallbackReentrancyTest is PoolTestBase {
    CallbackReserveToken internal callbackToken;
    bytes32 internal CALLBACK_ID;

    function setUp() public override {
        super.setUp();
        callbackToken = new CallbackReserveToken(pool);
        _addReserve("cUSD", address(callbackToken), usdtFeed);
        CALLBACK_ID = pool.getReserveId("cUSD");
        callbackToken.mint(alice, 100_000e18);
        callbackToken.mint(bob, 100_000e18);
        vm.prank(alice);
        callbackToken.approve(address(pool), type(uint256).max);
        vm.prank(bob);
        callbackToken.approve(address(pool), type(uint256).max);
        vm.prank(alice);
        pool.deposit(CALLBACK_ID, 20_000e18);
        vm.prank(bob);
        pool.deposit(CALLBACK_ID, 1_000e18);
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _deposit(alice, WETH_ID, address(weth), 10e18);

        // The callback caller has valid balances, approvals and an open position.
        weth.mint(address(callbackToken), 100e18);
        wbtc.mint(address(callbackToken), 100e18);
        _deposit(address(callbackToken), WETH_ID, address(weth), 10e18);
        _deposit(address(callbackToken), WBTC_ID, address(wbtc), 1e18);
        _borrow(address(callbackToken), WBTC_ID, WETH_ID, 1e18, 0.05e18);
        vm.prank(address(callbackToken));
        weth.approve(address(pool), type(uint256).max);
        vm.prank(address(callbackToken));
        wbtc.approve(address(pool), type(uint256).max);

        _borrow(alice, WETH_ID, WBTC_ID, 0.01e18, 0.05e18);
        oracle.setPrice(wethFeed, 1_000e18);
        assertFalse(pool.checkPositionHealth(alice, 0));
        _borrow(bob, WETH_ID, CALLBACK_ID, 1_000e18, 0.05e18);
    }

    function _nestedAction(uint256 action) internal view returns (bytes memory) {
        if (action == 0) return abi.encodeCall(pool.deposit, (WETH_ID, 1e18));
        if (action == 1) return abi.encodeCall(pool.withdraw, (WETH_ID, 1e18));
        if (action == 2) return abi.encodeCall(pool.borrow, (WBTC_ID, WETH_ID, 1e18, 0.05e18));
        if (action == 3) return abi.encodeCall(pool.repay, (WBTC_ID, WETH_ID, 0, 0.1e18));
        return abi.encodeCall(pool.liquidate, (alice, 0));
    }

    function _outerAction(uint256 action) internal {
        vm.prank(bob);
        if (action == 0) pool.deposit(CALLBACK_ID, 1e18);
        else if (action == 1) pool.withdraw(CALLBACK_ID, 1e18);
        else if (action == 2) pool.borrow(WETH_ID, CALLBACK_ID, 1e18, 0.05e18);
        else if (action == 3) pool.repay(WETH_ID, CALLBACK_ID, 0, 1e18);
        else pool.liquidate(bob, 0);
    }

    function testFuzz_AllActionsBlockCrossReserveCallbacks(uint8 rawOuter, uint8 rawNested) public {
        uint256 outer = bound(uint256(rawOuter), 0, 4);
        uint256 nested = bound(uint256(rawNested), 0, 4);
        if (outer == 4) oracle.setPrice(wethFeed, 100e18);
        uint256 beforeClaim = pool.getUserDepositBalance(WETH_ID, address(callbackToken));
        uint256 beforeDebt = pool.getUserBorrowBalance(WETH_ID, address(callbackToken));
        uint256 beforeWeth = weth.balanceOf(address(callbackToken));
        uint256 beforeWbtc = wbtc.balanceOf(address(callbackToken));
        callbackToken.arm(_nestedAction(nested), false);
        _outerAction(outer);
        assertTrue(callbackToken.attempted());
        assertFalse(callbackToken.succeeded());
        assertEq(callbackToken.result(), abi.encodeWithSelector(ReentrancyGuard.ReentrancyGuardReentrantCall.selector));
        assertEq(pool.getUserDepositBalance(WETH_ID, address(callbackToken)), beforeClaim);
        assertEq(pool.getUserBorrowBalance(WETH_ID, address(callbackToken)), beforeDebt);
        assertEq(weth.balanceOf(address(callbackToken)), beforeWeth);
        assertEq(wbtc.balanceOf(address(callbackToken)), beforeWbtc);
        assertTrue(pool.getPosition(alice, 0).isOpen);
        // A successful outer action releases the guard for the next transaction.
        vm.prank(bob);
        pool.deposit(CALLBACK_ID, 1e18);
    }

    function test_PropagatedCallbackFailureRollsBackAndReleasesGuard() public {
        uint256 beforeTokens = callbackToken.balanceOf(bob);
        uint256 beforeClaim = pool.getUserDepositBalance(CALLBACK_ID, bob);
        uint256 beforeTotal = pool.getReserve(CALLBACK_ID).totalDeposits;
        callbackToken.arm(_nestedAction(1), true);
        vm.prank(bob);
        vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
        pool.deposit(CALLBACK_ID, 1e18);
        assertEq(callbackToken.balanceOf(bob), beforeTokens);
        assertEq(pool.getUserDepositBalance(CALLBACK_ID, bob), beforeClaim);
        assertEq(pool.getReserve(CALLBACK_ID).totalDeposits, beforeTotal);
        callbackToken.arm(bytes(""), false);
        vm.prank(bob);
        pool.deposit(CALLBACK_ID, 1e18);
    }

    function test_ControlNestedActionsAreValidOutsideCallback() public {
        vm.prank(address(callbackToken));
        pool.deposit(WETH_ID, 1e18);
        vm.prank(address(callbackToken));
        pool.withdraw(WETH_ID, 1e18);
        _borrow(address(callbackToken), WBTC_ID, WETH_ID, 1e18, 0.05e18);
        vm.prank(address(callbackToken));
        pool.repay(WBTC_ID, WETH_ID, 0, 0.1e18);
        vm.prank(address(callbackToken));
        pool.liquidate(alice, 0);
        assertFalse(pool.getPosition(alice, 0).isOpen);
    }
}
