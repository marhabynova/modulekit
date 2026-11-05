// SPDX-License-Identifier: MIT
pragma solidity >=0.8.23 <0.9.0;

import "forge-std/Test.sol";
import { SchedulingBase } from "src/module-bases/SchedulingBase.sol";

contract MockScheduler is SchedulingBase {
    function onInstall(bytes calldata data) external {
        _onInstall(data);
    }

    function onUninstall(bytes calldata) external {
        _onUninstall();
    }

    function executeOrder(uint256 jobId) external canExecute(jobId) {
        ExecutionConfig storage executionConfig = executionLog[msg.sender][jobId];
        executionConfig.lastExecutionTime = uint48(block.timestamp);
        executionConfig.numberOfExecutionsCompleted += 1;
        emit ExecutionTriggered(msg.sender, jobId);
    }
}

contract SchedulingBaseTest is Test {
    MockScheduler internal scheduler;
    address internal user = address(0x1234);

    function setUp() public {
        scheduler = new MockScheduler();
    }

    function test_FirstExecutionNotGatedByInterval() public {
        uint48 executeInterval = 100 * 365 days;
        uint16 numberOfExecutions = 2;
        uint48 startDate = uint48(block.timestamp);
        bytes memory executionData = "";

        vm.prank(user);
        scheduler.onInstall(abi.encodePacked(executeInterval, numberOfExecutions, startDate, executionData));

        // First execution at startDate must succeed
        vm.prank(user);
        scheduler.executeOrder(1);

        (,, uint16 completed,, bool isEnabled, uint48 lastExecutionTime,) = scheduler.executionLog(user, 1);
        assertEq(completed, 1);
        assertTrue(isEnabled);
        assertEq(lastExecutionTime, uint48(block.timestamp));

        // Immediate second execution must revert because interval has not passed
        vm.prank(user);
        vm.expectRevert(SchedulingBase.InvalidExecution.selector);
        scheduler.executeOrder(1);

        // Warp past the interval
        vm.warp(block.timestamp + executeInterval);
        vm.prank(user);
        scheduler.executeOrder(1);

        (,, completed,,,,) = scheduler.executionLog(user, 1);
        assertEq(completed, 2);
    }

    function test_ExecutionBeforeStartDateReverts() public {
        uint48 executeInterval = 1 days;
        uint16 numberOfExecutions = 1;
        uint48 startDate = uint48(block.timestamp + 10 days);

        vm.prank(user);
        scheduler.onInstall(abi.encodePacked(executeInterval, numberOfExecutions, startDate, hex""));

        vm.prank(user);
        vm.expectRevert(SchedulingBase.InvalidExecution.selector);
        scheduler.executeOrder(1);
    }
}
