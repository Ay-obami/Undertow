// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @notice Incoming reserve payments must deliver their full accounting amount.
library TokenTransferLib {
    using SafeERC20 for IERC20;

    error UnexpectedTokenReceipt(address token, uint256 expected, uint256 received);

    function pullExact(IERC20 token, address from, uint256 amount) internal {
        uint256 beforeBalance = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);
        uint256 afterBalance = token.balanceOf(address(this));
        uint256 received = afterBalance >= beforeBalance ? afterBalance - beforeBalance : 0;
        if (afterBalance < beforeBalance || received != amount) {
            revert UnexpectedTokenReceipt(address(token), amount, received);
        }
    }
}
