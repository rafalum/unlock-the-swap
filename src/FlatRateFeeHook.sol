// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseHook} from "v4-periphery/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";

import {IUnlockV12} from "unlock/packages/contracts/src/contracts/Unlock/IUnlockV12.sol";
import {IPublicLockV13} from "unlock/packages/contracts/src/contracts/PublicLock/IPublicLockV13.sol";

contract FlatRateFeeHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    // Unlock smart contract (used to create a new lock)
    IUnlockV12 public unlock;

    // Mapping from pool to lock contract
    mapping(PoolId => address) public lockContracts;

    constructor(IPoolManager _poolManager, IUnlockV12 _unlock) BaseHook(_poolManager) {
        unlock = _unlock;
    }

    function getHooksCalls() public pure override returns (Hooks.Calls memory) {
        return Hooks.Calls({
            beforeInitialize: false,
            afterInitialize: true,
            beforeModifyPosition: false,
            afterModifyPosition: false,
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false
        });
    }  

    function afterInitialize(address, PoolKey calldata poolKey, uint160, int24, bytes calldata hookData)
        external
        override
        poolManagerOnly
        returns (bytes4)
    {   
        PoolId poolId = poolKey.toId();

        // Decode the hook data as the parameters for the new lock        
        (address _tokenAddress, uint256 _expirationDuration, uint256 _keyPrice, uint256 _maxNumberOfKeys) = abi.decode(hookData, (address, uint256, uint256, uint256));
        string memory _lockName = string.concat("Lock_", string(abi.encodePacked(PoolId.unwrap(poolId))));
        bytes12 _salt = bytes12(0);

        // Create the lock
        address lockAddress =
            unlock.createLock(_expirationDuration, _tokenAddress, _keyPrice, _maxNumberOfKeys, _lockName, _salt);

        lockContracts[poolId] = lockAddress;

        return BaseHook.afterInitialize.selector;
    }


    function getFee(address sender, PoolKey calldata poolKey, IPoolManager.SwapParams calldata, bytes calldata hookData) 
        external 
        view
        returns (uint24 newFee) 
    {
        PoolId poolId = poolKey.toId();
        IPublicLockV13 lockContract = IPublicLockV13(lockContracts[poolId]);

        address poolManager = msg.sender; // pool manager
        address poolSwap = sender; // poolSwap
        address swapper = abi.decode(hookData, (address)); // swapper

        if (lockContract.balanceOf(swapper) > 0) {
            return 0;
        } else {
            return 20000;
        }
    }

}
