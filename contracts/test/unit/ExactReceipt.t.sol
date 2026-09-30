// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolTestBase} from "./PoolTestBase.sol";

/// @dev Returns success while burning a configurable part of transferFrom.
/// Plain transfer remains exact so these tests isolate incoming accounting.
contract ShortReceiptToken {
    uint8 public constant decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public feeBps;

    function setFee(uint256 bps) external {
        require(bps <= 1000);
        feeBps = bps;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount - amount * feeBps / 10_000;
        return true;
    }
}

contract ExactReceiptTest is PoolTestBase {
    ShortReceiptToken internal token;
    bytes32 internal TOKEN_ID;
    address internal liquidator = makeAddr("liquidator");

    function setUp() public override {
        super.setUp();
        token = new ShortReceiptToken();
        _addReserve("short-receipt", address(token), usdtFeed);
        TOKEN_ID = pool.getReserveId("short-receipt");
        token.mint(alice, 1_000_000e18);
        token.mint(bob, 1_000_000e18);
    }

    function _seedAndBorrow() internal {
        vm.startPrank(alice);
        token.approve(address(pool), 500_000e18);
        pool.deposit(TOKEN_ID, 500_000e18);
        vm.stopPrank();
        _deposit(bob, WETH_ID, address(weth), 10e18);
        _borrow(bob, WETH_ID, TOKEN_ID, 5_000e18, 0.1e18);
    }

    function _expectShortReceipt(uint256 amount) internal {
        vm.expectRevert(
            abi.encodeWithSignature(
                "UnexpectedTokenReceipt(address,uint256,uint256)",
                address(token),
                amount,
                amount - amount * token.feeBps() / 10_000
            )
        );
    }

    function testFuzz_DepositRejectsShortReceipt(uint96 rawAmount, uint16 rawFee) public {
        uint256 amount = bound(uint256(rawAmount), 10_000, 100_000e18);
        token.setFee(bound(uint256(rawFee), 1, 1000));
        vm.startPrank(alice);
        token.approve(address(pool), amount);
        _expectShortReceipt(amount);
        pool.deposit(TOKEN_ID, amount);
        vm.stopPrank();
        assertEq(pool.getReserve(TOKEN_ID).totalDeposits, 0);
        assertEq(pool.getUserDepositBalance(TOKEN_ID, alice), 0);
        assertEq(token.balanceOf(address(pool)), 0);
        assertEq(token.balanceOf(alice), 1_000_000e18);
    }

    function test_RepayRejectsShortReceiptWithoutReleasingCollateral() public {
        _seedAndBorrow();
        uint256 beforeCash = token.balanceOf(address(pool));
        uint256 beforeCollateral = pool.getUserDepositBalance(WETH_ID, bob);
        token.setFee(1000);
        vm.startPrank(bob);
        token.approve(address(pool), 2_500e18);
        _expectShortReceipt(2_500e18);
        pool.repay(WETH_ID, TOKEN_ID, 0, 2_500e18);
        vm.stopPrank();
        assertEq(pool.getUserBorrowBalance(TOKEN_ID, bob), 5_000e18);
        assertEq(pool.getReserve(TOKEN_ID).totalBorrows, 5_000e18);
        assertEq(pool.getUserDepositBalance(WETH_ID, bob), beforeCollateral);
        assertEq(token.balanceOf(address(pool)), beforeCash);
    }

    function test_FullRepayRejectsShortReceiptWithoutClosingPosition() public {
        _seedAndBorrow();
        token.setFee(1000);
        vm.startPrank(bob);
        token.approve(address(pool), 5_000e18);
        _expectShortReceipt(5_000e18);
        pool.repay(WETH_ID, TOKEN_ID, 0, 5_000e18);
        vm.stopPrank();
        assertEq(pool.getUserPositions(bob).length, 1);
        assertEq(pool.getUserBorrowBalance(TOKEN_ID, bob), 5_000e18);
    }

    function test_LiquidationRejectsShortReceiptWithoutSeizingCollateral() public {
        _seedAndBorrow();
        oracle.setPrice(wethFeed, 2_500 * RAY);
        token.mint(liquidator, 5_000e18);
        token.setFee(1000);
        uint256 beforeCash = token.balanceOf(address(pool));
        uint256 beforeCollateral = weth.balanceOf(address(pool));
        vm.startPrank(liquidator);
        token.approve(address(pool), 5_000e18);
        _expectShortReceipt(5_000e18);
        pool.liquidate(bob, 0);
        vm.stopPrank();
        assertEq(pool.getUserPositions(bob).length, 1);
        assertEq(pool.getReserve(TOKEN_ID).totalBorrows, 5_000e18);
        assertEq(token.balanceOf(address(pool)), beforeCash);
        assertEq(weth.balanceOf(address(pool)), beforeCollateral);
        assertEq(weth.balanceOf(liquidator), 0);
    }

    function test_ExactReceiptStillAllowsDepositAndRepay() public {
        _seedAndBorrow();
        uint256 beforeCash = token.balanceOf(address(pool));
        vm.startPrank(bob);
        token.approve(address(pool), 5_000e18);
        pool.repay(WETH_ID, TOKEN_ID, 0, 5_000e18);
        vm.stopPrank();
        assertEq(token.balanceOf(address(pool)), beforeCash + 5_000e18);
        assertEq(pool.getUserPositions(bob).length, 0);
        assertEq(pool.getReserve(TOKEN_ID).totalBorrows, 0);
    }
}
