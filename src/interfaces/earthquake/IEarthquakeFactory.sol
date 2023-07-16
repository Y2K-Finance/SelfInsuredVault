// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IEarthquakeFactory {
    function getVaults(uint256) external view returns (address[2] memory);

    function getEpochsByMarketId(
        uint256
    ) external view returns (uint256[] memory);
}
