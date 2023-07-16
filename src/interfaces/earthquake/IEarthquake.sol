// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IEarthquake {
    function idEpochBegin(uint256) external view returns (uint256);

    function asset() external view returns (address asset);

    function emissionsToken() external view returns (address);

    function deposit(uint256 pid, uint256 amount, address to) external;

    function depositETH(uint256 pid, address to) external payable;

    function withdraw(
        uint256 id,
        uint256 assets,
        address receiver,
        address owner
    ) external returns (uint256 shares);

    function previewWithdraw(
        uint256 _id,
        uint256 _shares
    ) external view returns (uint256 entitledAssets);

    function previewEmissionsWithdraw(
        uint256 _id,
        uint256 _assets
    ) external view returns (uint256);

    function balanceOf(
        address account,
        uint256 id
    ) external view returns (uint256);

    function getVaults(uint256 pid) external view returns (address[2] memory);

    function getEpochsLength() external view returns (uint256);

    function epochs() external view returns (uint256[] memory);

    function epochs(uint256) external view returns (uint256);

    function getEpochConfig(uint256) external view returns (uint40, uint40);

    function epochResolved(uint256 _id) external view returns (bool);
}
