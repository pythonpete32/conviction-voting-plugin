// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.0;

import {IPriceOracle} from "../../src/interfaces/IPriceOracle.sol";

contract MockPriceOracle is IPriceOracle {
    uint256 public requestTokenPriceInStableToken;

    constructor(uint256 _requestTokenPriceInStableToken) {
        requestTokenPriceInStableToken = _requestTokenPriceInStableToken;
    }

    function consult(
        address tokenIn,
        uint256 amountIn,
        address tokenOut
    ) external view returns (uint256 amountOut) {
        (tokenIn, tokenOut);
        return amountIn / requestTokenPriceInStableToken;
    }
}
