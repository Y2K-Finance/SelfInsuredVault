// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

contract Helper is Test {
    // Users and wallets
    address public constant ADMIN = address(0x1);
    address public constant TREASURY = address(0x777);
    address public constant NOTADMIN = address(0x99);
    address public constant USER = address(0x85535e083c50f0C39a860243B9d1FAcFDbe8705a);
    address public constant USER2 = address(0x12312);
    address public constant RELAYER = address(0x55);

    // Assets
    address public constant WETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address public constant USDC_TOKEN = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address public constant STG_TOKEN = address(0x6694340fc020c5E6B96567843da2df01b2CE1eb6);
    address public constant STG_LPTOKEN = address(0x892785f33CdeE22A30AEF750F285E18c18040c3e);

    // Contracts
    address public constant ARBITRUM_SEQUENCER = address(0xFdB631F5EE196F0ed6FAa767959853A9F217697D);
    address public constant USDC_CHAINLINK = address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3);
    address public constant SUSHISWAP_ROUTER = address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
    address public constant STG_STAKING = address(0xeA8DfEE1898a7e0a59f7527F076106d7e44c2176);

    // Stargate info
    uint256 public constant STG_PID = 0;

    // Earthquake params
    uint256 public constant STRIKE = 1000000000000000000;
    uint256 public constant COLLATERAL_MINUS_FEES = 21989999998398551453;
    uint256 public constant COLLATERAL_MINUS_FEES_DIV10 = 2198999999839855145;
    uint256 public constant NEXT_COLLATERAL_MINUS_FEES = 21827317001324992496;
    uint256 public constant USER1_EMISSIONS_AFTER_WITHDRAW = 1096655439903230405190;
    uint256 public constant USER2_EMISSIONS_AFTER_WITHDRAW = 96655439903230405190;
    uint256 public constant USER_AMOUNT_AFTER_WITHDRAW = 13112658495821846450;

    // fee
    uint16 public fee = 50; // 0.5%
}
