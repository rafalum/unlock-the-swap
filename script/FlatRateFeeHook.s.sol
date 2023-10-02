// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolModifyPositionTest} from "@uniswap/v4-core/contracts/test/PoolModifyPositionTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";
import {PoolDonateTest} from "@uniswap/v4-core/contracts/test/PoolDonateTest.sol";
import {HookMiner} from "../test/utils/HookMiner.sol";

import {FlatRateFeeHook} from "../src/FlatRateFeeHook.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {Unlock} from "unlock/packages/contracts/src/contracts/Unlock/UnlockV12.sol";
import {PublicLock} from "unlock/packages/contracts/src/contracts/PublicLock/PublicLockV13.sol";

import {IUnlockV12} from "unlock/packages/contracts/src/contracts/Unlock/IUnlockV12.sol";
import {IPublicLockV13} from "unlock/packages/contracts/src/contracts/PublicLock/IPublicLockV13.sol";

/// @notice Forge script for deploying v4 & hooks to **anvil**
/// @dev This script only works on an anvil RPC because v4 exceeds bytecode limits
contract FlatRateFeeHookScript is Script {
    address constant CREATE2_DEPLOYER = address(0x4e59b44847b379578588920cA78FbF26c0B4956C);

    function setUp() public {}

    function run() public {
        vm.broadcast();

        // create the unlock contract which serves as a factory for locks
        address unlock = address(new Unlock());

        // create proxy for unlock contract
        bytes memory data = abi.encodeCall(Unlock.initialize, address(this));
        address proxy = address(new ERC1967Proxy(unlock, data));

        // create a new public lock template
        address impl = address(new PublicLock());

        // add and set lock template
        IUnlockV12(proxy).addLockTemplate(impl, 1);
        IUnlockV12(proxy).setLockTemplate(payable(impl));

        IUnlockV12 unlockProxy = IUnlockV12(proxy);

        PoolManager manager = new PoolManager(500000);

        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG);

        // Mine a salt that will produce a hook address with the correct flags
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, 1000, type(FlatRateFeeHook).creationCode, abi.encode(address(manager), address(unlockProxy)));

        // Deploy the hook using CREATE2
        vm.broadcast();
        FlatRateFeeHook flatRateFeeHook = new FlatRateFeeHook{salt: salt}(IPoolManager(address(manager)), IUnlockV12(address(unlockProxy)));
        require(address(flatRateFeeHook) == hookAddress, "FlatRateFeeHookScript: hook address mismatch");

        // Additional helpers for interacting with the pool
        vm.startBroadcast();
        new PoolModifyPositionTest(IPoolManager(address(manager)));
        new PoolSwapTest(IPoolManager(address(manager)));
        new PoolDonateTest(IPoolManager(address(manager)));
        vm.stopBroadcast();
    }
}