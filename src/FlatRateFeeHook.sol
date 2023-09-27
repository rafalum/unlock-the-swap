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

        address _tokenAddress;
        if (hookData.length == 0) {
            // `hookData` is not set to anything -> use currency0 as token address
            _tokenAddress = Currency.unwrap(poolKey.currency0);
        } else {
            // `hookData` contains data
            _tokenAddress = _bytesToAddress(hookData);
        }

        // Create a lock for the poolKey        
        uint256 _expirationDuration = 2_592_000; // 30 days
        uint256 _keyPrice = 10_000_000_000_000_000; // 0.01 ETH
        uint256 _maxNumberOfKeys = 1000;
        string memory _lockName = string.concat("Lock_", string(abi.encodePacked(PoolId.unwrap(poolId))));
        bytes12 _salt = bytes12(0);

        address lockAddress =
            unlock.createLock(_expirationDuration, _tokenAddress, _keyPrice, _maxNumberOfKeys, _lockName, _salt);

        lockContracts[poolId] = lockAddress;

        return BaseHook.afterInitialize.selector;
    }


    function getFee(address sender, PoolKey calldata poolKey, IPoolManager.SwapParams calldata, bytes calldata) 
        external 
        view
        returns (uint24 newFee) 
    {
        PoolId poolId = poolKey.toId();
        IPublicLockV13 lockContract = IPublicLockV13(lockContracts[poolId]);

        if (lockContract.balanceOf(sender) > 0) {
            return 0;
        } else {
            return 20000;
        }
    }



    function _bytesToAddress(bytes memory bys) internal pure returns (address) {
        require(bys.length == 20, "Invalid address length"); // Check that the input bytes are 20 bytes long (160 bits)
        address addr;
        assembly {
            addr := mload(add(bys, 0x14)) // Load the 20 bytes from memory and store it as an address
        }
        return addr;
    }

}
