// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {BaseHook} from "v4-periphery/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/contracts/types/BalanceDelta.sol";
import {IERC20Minimal} from "@uniswap/v4-core/contracts/interfaces/external/IERC20Minimal.sol";

import {IUnlockV12} from "unlock/packages/contracts/src/contracts/Unlock/IUnlockV12.sol";
import {IPublicLockV13} from "unlock/packages/contracts/src/contracts/PublicLock/IPublicLockV13.sol";

contract FlatRateFeeHook is BaseHook {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    // Unlock smart contract (used to create a new lock)
    IUnlockV12 public unlock;

    // Mapping from pool to lock contract
    mapping(PoolId => address) public lockContracts;

    // CallbackData for donate functionality
    struct CallbackData {
        address sender;
        PoolKey key;
        uint256 amount0;
        uint256 amount1;
    }

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


    function getFee(address, PoolKey calldata poolKey, IPoolManager.SwapParams calldata, bytes calldata hookData) 
        external 
        view
        returns (uint24 newFee) 
    {
        PoolId poolId = poolKey.toId();
        IPublicLockV13 lockContract = IPublicLockV13(lockContracts[poolId]);

        // address poolManager = msg.sender;
        // address poolSwap = sender;
        address swapper = abi.decode(hookData, (address)); // swapper

        if (lockContract.balanceOf(swapper) > 0) {
            return 0;
        } else {
            return 20000;
        }
    }

    /// @notice Purchases a subscription to trade without fees and returns the token ID
    /// @param poolKey The pool to purchase a membership for
    /// @param value The amount of tokens to send
    /// @return tokenId The ID of the purchased subscription
    function purchaseSubscription(PoolKey calldata poolKey, uint256 value) 
        external 
        payable
        returns (uint256 tokenId) 
    {
        PoolId poolId = poolKey.toId();
        IPublicLockV13 lockContract = IPublicLockV13(lockContracts[poolId]);

        IERC20Minimal tokenContract = IERC20Minimal(lockContract.tokenAddress());

        uint256[] memory _values = new uint256[](1);
        _values[0] = value;

        address[] memory _recipients = new address[](1);
        _recipients[0] = msg.sender;

        address[] memory _referrers = new address[](1);
        _referrers[0] = msg.sender;

        address[] memory _keyManagers = new address[](1);
        _keyManagers[0] = msg.sender;

        bytes[] memory _data = new bytes[](1);
        _data[0] = bytes("0x");

        tokenContract.transferFrom(msg.sender, address(this), value);
        tokenContract.approve(address(lockContract), value);

        uint256[] memory tokenIds = lockContract.purchase(
            _values,
            _recipients,
            _referrers,
            _keyManagers,
            _data
        );
        tokenId = tokenIds[0];

        uint256 lockedAmount = tokenContract.balanceOf(address(lockContract));

        _withdrawAndDonate(poolKey, lockedAmount);
    }

    /// @notice Withdraws the tokens from the lock and donates them to the pool
    /// @param poolKey The pool to donate to
    /// @param amount The amount of tokens to withdraw
    function _withdrawAndDonate(PoolKey calldata poolKey, uint256 amount) 
        internal 
    {
        PoolId poolId = poolKey.toId();
        IPublicLockV13 lockContract = IPublicLockV13(lockContracts[poolId]);

        address tokenAddress = lockContract.tokenAddress();

        lockContract.withdraw(
            tokenAddress,
            payable(address(this)),
            amount
        );

        uint256 amount0 = 0;
        uint256 amount1 = 0;

        // check which currency to donate
        if (Currency.unwrap(poolKey.currency0) == tokenAddress) {
            amount0 = amount;
        } else if (Currency.unwrap(poolKey.currency1) == tokenAddress) {
            amount1 = amount;
        } else {
            // purchase token is different from pool token pair -> swap token to one of the pool tokens
            // TODO - implement handling for this case
            revert("Not handled");
        }

        // donate the tokens to the pool
        BalanceDelta delta = abi.decode(poolManager.lock(abi.encode(CallbackData(msg.sender, poolKey, amount0, amount1))), (BalanceDelta));

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }

    }

    ///@notice Callback to donate the tokens to the pool
    ///@param rawData The data passed to the callback
    function lockAcquired(bytes calldata rawData) 
        external
        override
        poolManagerOnly 
        returns (bytes memory) 
    {
        CallbackData memory data = abi.decode(rawData, (CallbackData));

        BalanceDelta delta = poolManager.donate(data.key, data.amount0, data.amount1, new bytes(0));

        if (delta.amount0() > 0) {
            if (data.key.currency0.isNative()) {
                poolManager.settle{value: uint128(delta.amount0())}(data.key.currency0);
            } else {
                IERC20Minimal(Currency.unwrap(data.key.currency0)).transferFrom(
                    data.sender, address(poolManager), uint128(delta.amount0())
                );
                poolManager.settle(data.key.currency0);
            }
        }
        if (delta.amount1() > 0) {
            if (data.key.currency1.isNative()) {
                poolManager.settle{value: uint128(delta.amount1())}(data.key.currency1);
            } else {
                IERC20Minimal(Currency.unwrap(data.key.currency1)).transferFrom(
                    data.sender, address(poolManager), uint128(delta.amount1())
                );
                poolManager.settle(data.key.currency1);
            }
        }

        return abi.encode(delta);
    }

}
