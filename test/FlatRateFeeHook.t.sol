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
        bytes memory hookData = abi.encode(
            address(token0),    // fee token
            2_592_00,           // 30 days
            0.1*10**18,         // 0.1 of token0
            100                 // 100 keys
        );
        manager.initialize(poolKey, SQRT_RATIO_1_1, hookData);

        // Provide liquidity to the pool
        modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-60, 60, 10 ether));
        modifyPositionRouter.modifyPosition(poolKey, IPoolManager.ModifyPositionParams(-120, 120, 10 ether));
        modifyPositionRouter.modifyPosition(
            poolKey, IPoolManager.ModifyPositionParams(TickMath.minUsableTick(60), TickMath.maxUsableTick(60), 10 ether)
        );

        console2.log("pool manager", address(manager));
        console2.log("swap router", address(swapRouter));
        console2.log("donate router", address(donateRouter));
        console2.log("modify position router", address(modifyPositionRouter));
    }

    function testInitialize() public {
        // retrieve the lock contract for the pool
        address lockAddress = hookContract.lockContracts(poolId);

        // check that the unlock contract matches the one we passed in
        assertEq(address(hookContract.unlock()), address(unlockProxy));

        // check that the owner of the created lock is the hook contract
        assertEq(IPublicLockV13(lockAddress).owner(), address(hookContract));

        // check that the fee token equals token0
        assertEq(IPublicLockV13(lockAddress).tokenAddress(), address(token0));
    }

    function testPurchaseKey() public {
        // retrieve the lock contract for the pool
        address lockAddress = hookContract.lockContracts(poolId);
        address user = address(1337);

        // check that the user has no keys
        assertEq(IPublicLockV13(lockAddress).balanceOf(user), 0);

        // mint and approve tokens
        _mintAndApprove(user, lockAddress, 10**18);
        // purchase a key
        _purchaseKey(lockAddress, user);

        // check that the user has 1 key
        assertEq(IPublicLockV13(lockAddress).balanceOf(user), 1);
    }

    function testSwap() public {
        // retrieve the lock contract for the pool
        address lockAddress = hookContract.lockContracts(poolId);
        address user = address(swapRouter);

        // mint and approve tokens
        _mintAndApprove(user, lockAddress, 10**18);
    
        _purchaseKey(lockAddress, user);

        // mint and approve tokens
        _mintAndApprove(user, address(swapRouter), 10**18);
        
        // Perform a test swap
        int256 amount = 0.5 * 10**18;
        bool zeroForOne = true;

        vm.startBroadcast(user);
        swap(poolKey, amount, true);
        vm.stopBroadcast();

        // check balance of user
        uint256 balanceToken1 = token1.balanceOf(user);

        console2.log(balanceToken1);   
    }

    function _mintAndApprove(address user, address spender, uint256 amount) public {
        token0.mint(user, amount);
        vm.prank(user);
        token0.approve(spender, amount);
    }

    function _purchaseKey(address lockAddress, address buyer) public returns (uint256) {
        vm.prank(buyer);

        // create a new key
        uint256[] memory _values = new uint256[](1);
        _values[0] = 0.1*10**18;

        address[] memory _recipients = new address[](1);
        _recipients[0] = buyer;

        address[] memory _referrers = new address[](1);
        _referrers[0] = buyer;

        address[] memory _keyManagers = new address[](1);
        _keyManagers[0] = buyer;

        bytes[] memory _data = new bytes[](1);
        _data[0] = bytes("0x");

        uint256[] memory tokenIds = IPublicLockV13(lockAddress).purchase(_values, _recipients, _referrers, _keyManagers, _data);
        return tokenIds[0];
    }

}
