// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import {Unlock} from "unlock/packages/contracts/src/contracts/Unlock/UnlockV12.sol";
import {PublicLock} from "unlock/packages/contracts/src/contracts/PublicLock/PublicLockV13.sol";

import {IUnlockV12} from "unlock/packages/contracts/src/contracts/Unlock/IUnlockV12.sol";
import {IPublicLockV13} from "unlock/packages/contracts/src/contracts/PublicLock/IPublicLockV13.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @notice Contract to initialize unlock factory
contract UnlockTest is Test {

    IUnlockV12 unlockProxy;

    function initUnlockTestEnv() public {
        address deployer = address(42);
        vm.startBroadcast(deployer);

        // create the unlock contract which serves as a factory for locks
        address unlock = address(new Unlock());

        // create proxy for unlock contract
        bytes memory data = abi.encodeCall(Unlock.initialize, deployer);
        address proxy = address(new ERC1967Proxy(unlock, data));

        // create a new public lock template
        address impl = address(new PublicLock());

        // add and set lock template
        IUnlockV12(proxy).addLockTemplate(impl, 1);
        IUnlockV12(proxy).setLockTemplate(payable(impl));

        vm.stopBroadcast();

        unlockProxy = IUnlockV12(proxy);
    }

}
