// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.19;

interface IPriceOracle {
    function consult(
        address tokenIn,
        uint amountIn,
        address tokenOut
    ) external view returns (uint amountOut);
}
