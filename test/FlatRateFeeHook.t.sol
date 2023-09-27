// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {Deployers} from "@uniswap/v4-core/test/foundry-tests/utils/Deployers.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {Fees} from "@uniswap/v4-core/contracts/Fees.sol";
import {FeeLibrary} from "@uniswap/v4-core/contracts/libraries/FeeLibrary.sol";

import {HookTest} from "./utils/HookTest.sol";
import {HookMiner} from "./utils/HookMiner.sol";
import {UnlockTest} from "./utils/UnlockTest.sol";

import {FlatRateFeeHook} from "../src/FlatRateFeeHook.sol";

import {IUnlockV12} from "unlock/packages/contracts/src/contracts/Unlock/IUnlockV12.sol";
import {IPublicLockV13} from "unlock/packages/contracts/src/contracts/PublicLock/IPublicLockV13.sol";


contract FlatRateFeeHockTest is HookTest, UnlockTest, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    FlatRateFeeHook hookContract;
    PoolKey poolKey;
    PoolId poolId;

    function setUp() public {
        // creates the pool manager, test tokens, and other utility routers
        HookTest.initHookTestEnv();

        // creates the unlock factory and adds and sets a lock template
        UnlockTest.initUnlockTestEnv();

        // Deploy the hook to an address with the correct flags
        uint160 flags = uint160(Hooks.AFTER_INITIALIZE_FLAG);

        (address hookAddress, bytes32 salt) = HookMiner.find(address(this), flags, 0, type(FlatRateFeeHook).creationCode, abi.encode(address(manager), address(unlockProxy)));
        hookContract = new FlatRateFeeHook{salt: salt}(IPoolManager(address(manager)), IUnlockV12(address(unlockProxy)));
        require(address(hookContract) == hookAddress, "hook address mismatch");

        // Dynamic Fee
        uint24 dynamicFee = FeeLibrary.DYNAMIC_FEE_FLAG;

        // Create the pool
        poolKey = PoolKey(Currency.wrap(address(token0)), Currency.wrap(address(token1)), dynamicFee, 60, IHooks(hookContract));
        poolId = poolKey.toId();
        manager.initialize(poolKey, SQRT_RATIO_1_1, ZERO_BYTES);

        // Provide liquidity to the pool
        modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-60, 60, 10 ether));
        modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-120, 120, 10 ether));
        modifyPositionRouter.modifyPosition(
            poolKey, IPoolManager.ModifyPositionParams(TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 10 ether)
        );
    }

    function testInitialize() public {
        assertEq(address(hookContract.unlock()), address(unlockProxy));

        address lockAddress = hookContract.lockContracts(poolId);

        console2.logAddress(lockAddress);   
        console2.logAddress(IPublicLockV13(lockAddress).owner());
    }

}
