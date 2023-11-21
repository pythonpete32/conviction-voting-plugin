// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.8.19;

library ArrayUtils {
    function deleteItem(uint256[] storage self, uint256 item) internal returns (bool) {
        uint256 length = self.length;
        for (uint256 i = 0; i < length; i++) {
            if (self[i] == item) {
                uint256 newLength = self.length - 1;
                if (i != newLength) {
                    self[i] = self[newLength];
                }

                // delete self[newLength];
                // self.length = newLength;

                // return true;
                // Delete the last element
                self.pop();
                return true;
            }
        }
        return false;
    }

    function contains(uint256[] storage self, uint256 item) internal view returns (bool) {
        for (uint256 i = 0; i < self.length; i++) {
            if (self[i] == item) {
                return true;
            }
        }
        return false;
    }
}
