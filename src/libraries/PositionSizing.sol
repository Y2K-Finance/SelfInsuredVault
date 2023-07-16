// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

library PositionSizer {
    error InvalidWeightStrategy();

    //////////////////////////////////////////////
    //                 EXTERNAL                 //
    //////////////////////////////////////////////
    function fetchWeights(
        address[] memory vaults,
        uint256 availableAmount,
        uint256 weightStrategy
    ) external view returns (uint256[] memory amounts) {
        if (weightStrategy == 0)
            return _equalWeight(availableAmount, vaults.length);
        else if (weightStrategy == 1)
            return _bespokeWeight(availableAmount, vaults);
        else if (weightStrategy == 2) return _systemWeight(availableAmount);
        else revert InvalidWeightStrategy();
    }

    //////////////////////////////////////////////
    //                 INTERNAL                 //
    //////////////////////////////////////////////
    function _equalWeight(
        uint256 availableAmount,
        uint256 length
    ) internal pure returns (uint256[] memory amounts) {
        uint256 modulo = availableAmount % length;

        for (uint256 i = 0; i < length; ) {
            amounts[i] = availableAmount / length;
            if (modulo > 0) {
                amounts[i] += 1;
                modulo -= 1;
            }
            unchecked {
                i++;
            }
        }
    }

    function _bespokeWeight(
        uint256 availableAmount,
        address[] memory vaults
    ) internal view returns (uint256[] memory amounts) {}

    function _systemWeight(
        uint256 availableAmount
    ) internal view returns (uint256[] memory amounts) {}
}
