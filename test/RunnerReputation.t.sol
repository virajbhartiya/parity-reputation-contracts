// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/RunnerReputation.sol";

contract RunnerReputationTest is Test {
    RunnerReputation public reputation;
    
    address public owner;
    address public runner1Wallet = address(0x1);
    address public runner2Wallet = address(0x2);
    address public runner3Wallet = address(0x3);
    address public runner4Wallet = address(0x4);
    
    string public runner1 = "runner1";
    string public runner2 = "runner2";
    string public runner3 = "runner3";
    string public runner4 = "runner4";
    
    function setUp() public {
        owner = address(this);
        reputation = new RunnerReputation();
    }
    
    // ============ STAKING TESTS ============
    
    function testStakeDeposit() public {
        reputation.registerRunner(runner1, runner1Wallet);
        
        vm.expectEmit(true, true, false, true);
        emit RunnerReputation.StakeDeposited(runner1, runner1Wallet, 100 ether);
        
        reputation.depositStake(runner1, 100 ether);
        
        RunnerReputation.RunnerProfile memory profile = reputation.getRunnerProfile(runner1);
        assertEq(profile.stakedAmount, 100 ether);
        
        RunnerReputation.NetworkStats memory stats = reputation.getNetworkStats();
        assertEq(stats.totalStakedAmount, 100 ether);
    }
    
    function testStakeWithdrawal() public {
        reputation.registerRunner(runner1, runner1Wallet);
        reputation.depositStake(runner1, 100 ether);
        
        vm.expectEmit(true, true, false, true);
        emit RunnerReputation.StakeWithdrawn(runner1, runner1Wallet, 50 ether);
        
        reputation.withdrawStake(runner1, 50 ether);
        
        RunnerReputation.RunnerProfile memory profile = reputation.getRunnerProfile(runner1);
        assertEq(profile.stakedAmount, 50 ether);
    }
    
    function testStakeSlashing() public {
        reputation.registerRunner(runner1, runner1Wallet);
        reputation.depositStake(runner1, 100 ether);
        
        vm.expectEmit(true, true, false, true);
        emit RunnerReputation.SlashingExecuted(runner1, runner1Wallet, 20 ether, "Malicious behavior detected");
        
        uint256 slashedAmount = reputation.slashStake(runner1, "Malicious behavior detected");
        
        assertEq(slashedAmount, 20 ether); // 20% of 100 ether
        
        RunnerReputation.RunnerProfile memory profile = reputation.getRunnerProfile(runner1);
        assertEq(profile.stakedAmount, 80 ether);
        assertEq(profile.totalSlashed, 20 ether);
        assertEq(profile.reputationScore, 400); // 500 - 100 penalty
        
        RunnerReputation.NetworkStats memory stats = reputation.getNetworkStats();
        assertEq(stats.totalSlashedAmount, 20 ether);
        assertEq(stats.totalStakedAmount, 80 ether);
    }
    
    function testCannotWithdrawWhileBanned() public {
        reputation.registerRunner(runner1, runner1Wallet);
        reputation.depositStake(runner1, 100 ether);
        reputation.banRunner(runner1, "Test ban");
        
        vm.expectRevert("Cannot withdraw while banned");
        reputation.withdrawStake(runner1, 50 ether);
    }
    
    // ============ MONITORING TESTS ============
    
    function testMonitoringAssignment() public {
        // Register multiple runners with sufficient stake
        reputation.registerRunner(runner1, runner1Wallet);
        reputation.registerRunner(runner2, runner2Wallet);
        reputation.registerRunner(runner3, runner3Wallet);
        reputation.registerRunner(runner4, runner4Wallet);
        
        reputation.depositStake(runner1, 100 ether);
        reputation.depositStake(runner2, 100 ether);
        reputation.depositStake(runner3, 100 ether);
        reputation.depositStake(runner4, 100 ether);
        
        // Assign random monitoring
        reputation.assignRandomMonitoring();
        
        string[] memory activeAssignments = reputation.getActiveMonitoringAssignments();
        assertEq(activeAssignments.length, 2); // 4 runners = 2 monitoring pairs
        
        RunnerReputation.NetworkStats memory stats = reputation.getNetworkStats();
        assertEq(stats.activeMonitoringAssignments, 2);
    }
    
    function testMonitoringReportSubmission() public {
        // Setup runners and monitoring
        reputation.registerRunner(runner1, runner1Wallet);
        reputation.registerRunner(runner2, runner2Wallet);
        reputation.depositStake(runner1, 100 ether);
        reputation.depositStake(runner2, 100 ether);
        
        reputation.assignRandomMonitoring();
        string[] memory assignments = reputation.getActiveMonitoringAssignments();
        string memory assignmentId = assignments[0];
        
        RunnerReputation.MonitoringAssignment memory assignment = reputation.getMonitoringAssignment(assignmentId);
        
        vm.expectEmit(true, true, false, true);
        emit RunnerReputation.MonitoringReportSubmitted(
            assignment.monitorId, 
            assignment.targetId, 
            uint8(RunnerReputation.MonitoringReportType.GoodBehavior), 
            "ipfs://evidence-hash"
        );
        
        reputation.submitMonitoringReport(
            assignmentId,
            RunnerReputation.MonitoringReportType.GoodBehavior,
            "ipfs://evidence-hash"
        );
        
        // Check that report was processed
        RunnerReputation.MonitoringAssignment memory updatedAssignment = reputation.getMonitoringAssignment(assignmentId);
        assertTrue(updatedAssignment.reportSubmitted);
        assertTrue(updatedAssignment.verified);
        assertFalse(updatedAssignment.isActive);
    }
    
    function testMaliciousBehaviorReportTriggersSlashing() public {
        reputation.registerRunner(runner1, runner1Wallet);
        reputation.registerRunner(runner2, runner2Wallet);
        reputation.depositStake(runner1, 100 ether);
        reputation.depositStake(runner2, 100 ether);
        
        reputation.assignRandomMonitoring();
        string[] memory assignments = reputation.getActiveMonitoringAssignments();
        string memory assignmentId = assignments[0];
        
        RunnerReputation.MonitoringAssignment memory assignment = reputation.getMonitoringAssignment(assignmentId);
        
        // Get initial stake of target
        RunnerReputation.RunnerProfile memory initialProfile = reputation.getRunnerProfile(assignment.targetId);
        uint256 initialStake = initialProfile.stakedAmount;
        
        // Submit malicious behavior report
        reputation.submitMonitoringReport(
            assignmentId,
            RunnerReputation.MonitoringReportType.MaliciousBehavior,
            "ipfs://malicious-evidence"
        );
        
        // Check that slashing occurred
        RunnerReputation.RunnerProfile memory finalProfile = reputation.getRunnerProfile(assignment.targetId);
        assertTrue(finalProfile.stakedAmount < initialStake);
        assertTrue(finalProfile.totalSlashed > 0);
        assertEq(finalProfile.reputationScore, 350); // 500 - 50 (malicious) - 100 (slashing) = 350
    }
    
    function testMonitorRewards() public {
        reputation.registerRunner(runner1, runner1Wallet);
        reputation.registerRunner(runner2, runner2Wallet);
        reputation.depositStake(runner1, 100 ether);
        reputation.depositStake(runner2, 100 ether);
        
        reputation.assignRandomMonitoring();
        string[] memory assignments = reputation.getActiveMonitoringAssignments();
        string memory assignmentId = assignments[0];
        
        RunnerReputation.MonitoringAssignment memory assignment = reputation.getMonitoringAssignment(assignmentId);
        
        // Get initial profile of monitor
        RunnerReputation.RunnerProfile memory initialProfile = reputation.getRunnerProfile(assignment.monitorId);
        
        reputation.submitMonitoringReport(
            assignmentId,
            RunnerReputation.MonitoringReportType.GoodBehavior,
            "ipfs://evidence"
        );
        
        // Check monitor was rewarded
        RunnerReputation.RunnerProfile memory finalProfile = reputation.getRunnerProfile(assignment.monitorId);
        assertTrue(finalProfile.totalEarnings > initialProfile.totalEarnings);
        assertTrue(finalProfile.monitoringScore > initialProfile.monitoringScore);
        assertEq(finalProfile.reputationScore, 505); // 500 + 5 monitoring bonus
    }
    
    function testInsufficientStakePreventssMonitoring() public {
        reputation.registerRunner(runner1, runner1Wallet);
        reputation.registerRunner(runner2, runner2Wallet);
        
        // Only deposit small amounts (below minimum stake)
        reputation.depositStake(runner1, 1 ether);
        reputation.depositStake(runner2, 1 ether);
        
        vm.expectRevert("Need at least 2 active runners for monitoring");
        reputation.assignRandomMonitoring();
    }
    
    // ============ ELIGIBILITY TESTS ============
    
    function testEligibilityRequiresMinimumStake() public {
        reputation.registerRunner(runner1, runner1Wallet);
        
        // Without sufficient stake
        assertFalse(reputation.isRunnerEligible(runner1));
        
        // With sufficient stake
        reputation.depositStake(runner1, 100 ether);
        assertTrue(reputation.isRunnerEligible(runner1));
    }
    
    function testBannedRunnerNotEligible() public {
        reputation.registerRunner(runner1, runner1Wallet);
        reputation.depositStake(runner1, 100 ether);
        
        assertTrue(reputation.isRunnerEligible(runner1));
        
        reputation.banRunner(runner1, "Test ban");
        assertFalse(reputation.isRunnerEligible(runner1));
    }
    
    // ============ EXISTING TESTS (Updated) ============
    
    function testRegisterRunner() public {
        vm.expectEmit(true, true, false, true);
        emit RunnerReputation.RunnerRegistered(runner1, runner1Wallet);
        
        reputation.registerRunner(runner1, runner1Wallet);
        
        RunnerReputation.RunnerProfile memory profile = reputation.getRunnerProfile(runner1);
        assertEq(profile.runnerId, runner1);
        assertEq(profile.walletAddress, runner1Wallet);
        assertEq(profile.reputationScore, 500);
        assertEq(uint(profile.status), uint(RunnerReputation.RunnerStatus.Active));
        assertEq(profile.monitoringScore, 100); // New field
        assertEq(profile.stakedAmount, 0); // New field
    }
    
    function testCannotRegisterDuplicateRunner() public {
        reputation.registerRunner(runner1, runner1Wallet);
        
        vm.expectRevert("Runner already exists");
        reputation.registerRunner(runner1, runner2Wallet);
    }
    
    function testCannotRegisterDuplicateWallet() public {
        reputation.registerRunner(runner1, runner1Wallet);
        
        vm.expectRevert("Wallet already registered");
        reputation.registerRunner(runner2, runner1Wallet);
    }
    
    function testUpdateReputationTaskCompleted() public {
        reputation.registerRunner(runner1, runner1Wallet);
        
        vm.expectEmit(true, false, false, true);
        emit RunnerReputation.ReputationUpdated(runner1, 500, 510, "Task completed successfully");
        
        reputation.updateReputation(
            runner1,
            RunnerReputation.ReputationEventType.TaskCompleted,
            10,
            "Task completed successfully"
        );
        
        RunnerReputation.RunnerProfile memory profile = reputation.getRunnerProfile(runner1);
        assertEq(profile.reputationScore, 510);
        assertEq(profile.totalTasks, 1);
        assertEq(profile.successfulTasks, 1);
    }
    
    function testUpdateReputationTaskFailed() public {
        reputation.registerRunner(runner1, runner1Wallet);
        
        reputation.updateReputation(
            runner1,
            RunnerReputation.ReputationEventType.TaskFailed,
            -15,
            "Task execution failed"
        );
        
        RunnerReputation.RunnerProfile memory profile = reputation.getRunnerProfile(runner1);
        assertEq(profile.reputationScore, 485);
        assertEq(profile.totalTasks, 1);
        assertEq(profile.failedTasks, 1);
    }
    
    function testAutomaticBanningWhenReputationDrops() public {
        reputation.registerRunner(runner1, runner1Wallet);
        
        vm.expectEmit(true, true, false, true);
        emit RunnerReputation.RunnerBanned(runner1, runner1Wallet, "Reputation score below ban threshold");
        
        reputation.updateReputation(
            runner1,
            RunnerReputation.ReputationEventType.Malicious,
            -700,
            "Severe malicious behavior"
        );
        
        RunnerReputation.RunnerProfile memory profile = reputation.getRunnerProfile(runner1);
        assertEq(uint(profile.status), uint(RunnerReputation.RunnerStatus.Banned));
        assertTrue(reputation.isRunnerBanned(runner1));
        assertFalse(reputation.isRunnerEligible(runner1));
    }
    
    function testMaliciousBehaviorTracking() public {
        reputation.registerRunner(runner1, runner1Wallet);
        
        reputation.updateReputation(
            runner1,
            RunnerReputation.ReputationEventType.Malicious,
            -100,
            "Submitted invalid results"
        );
        
        RunnerReputation.RunnerProfile memory profile = reputation.getRunnerProfile(runner1);
        assertEq(profile.maliciousReports, 1);
    }
    
    function testManualBanning() public {
        reputation.registerRunner(runner1, runner1Wallet);
        
        vm.expectEmit(true, true, false, true);
        emit RunnerReputation.RunnerBanned(runner1, runner1Wallet, "Violation of terms");
        
        reputation.banRunner(runner1, "Violation of terms");
        
        assertTrue(reputation.isRunnerBanned(runner1));
        
        RunnerReputation.RunnerProfile memory profile = reputation.getRunnerProfile(runner1);
        assertEq(profile.banReason, "Violation of terms");
    }
    
    function testGetTopRunners() public {
        reputation.registerRunner(runner1, runner1Wallet);
        reputation.registerRunner(runner2, runner2Wallet);
        reputation.registerRunner(runner3, runner3Wallet);
        
        reputation.updateReputation(runner1, RunnerReputation.ReputationEventType.Bonus, 200, "High performance");
        reputation.updateReputation(runner2, RunnerReputation.ReputationEventType.Penalty, -50, "Poor performance");
        reputation.updateReputation(runner3, RunnerReputation.ReputationEventType.Bonus, 100, "Good performance");
        
        (string[] memory topRunners, int256[] memory scores) = reputation.getTopRunners(3);
        
        assertEq(topRunners[0], runner1);
        assertEq(scores[0], 700);
        assertEq(topRunners[1], runner3);
        assertEq(scores[1], 600);
        assertEq(topRunners[2], runner2);
        assertEq(scores[2], 450);
    }
    
    function testNetworkStats() public {
        reputation.registerRunner(runner1, runner1Wallet);
        reputation.registerRunner(runner2, runner2Wallet);
        reputation.depositStake(runner1, 100 ether);
        reputation.depositStake(runner2, 50 ether);
        
        reputation.updateReputation(runner1, RunnerReputation.ReputationEventType.TaskCompleted, 10, "Good job");
        reputation.updateReputation(runner2, RunnerReputation.ReputationEventType.TaskFailed, -15, "Failed task");
        
        reputation.banRunner(runner2, "Too many failures");
        
        RunnerReputation.NetworkStats memory stats = reputation.getNetworkStats();
        assertEq(stats.totalRunners, 2);
        assertEq(stats.activeRunners, 1);
        assertEq(stats.bannedRunners, 1);
        assertEq(stats.totalTasks, 2);
        assertEq(stats.totalStakedAmount, 150 ether);
    }
    
    function testReputationEventsHistory() public {
        reputation.registerRunner(runner1, runner1Wallet);
        
        reputation.updateReputation(runner1, RunnerReputation.ReputationEventType.TaskCompleted, 10, "First task");
        reputation.updateReputation(runner1, RunnerReputation.ReputationEventType.TaskCompleted, 10, "Second task");
        reputation.updateReputation(runner1, RunnerReputation.ReputationEventType.Bonus, 50, "High quality work");
        
        RunnerReputation.ReputationEvent[] memory events = reputation.getReputationEvents(runner1);
        assertEq(events.length, 3);
        assertEq(events[0].scoreDelta, 10);
        assertEq(events[1].scoreDelta, 10);
        assertEq(events[2].scoreDelta, 50);
    }
    
    function testOnlyAuthorizedCanUpdate() public {
        reputation.registerRunner(runner1, runner1Wallet);
        
        address unauthorized = address(0x999);
        vm.prank(unauthorized);
        vm.expectRevert("Not authorized");
        reputation.updateReputation(runner1, RunnerReputation.ReputationEventType.TaskCompleted, 10, "Should fail");
    }
    
    function testRunnerStatusProgression() public {
        reputation.registerRunner(runner1, runner1Wallet);
        
        (int256 score, RunnerReputation.RunnerStatus status,,,) = reputation.getRunnerStatus(runner1);
        assertEq(score, 500);
        assertEq(uint(status), uint(RunnerReputation.RunnerStatus.Active));
        
        reputation.updateReputation(runner1, RunnerReputation.ReputationEventType.Penalty, -100, "Poor performance");
        
        (, status,,,) = reputation.getRunnerStatus(runner1);
        assertEq(uint(status), uint(RunnerReputation.RunnerStatus.Warning));
        
        reputation.updateReputation(runner1, RunnerReputation.ReputationEventType.Malicious, -500, "Malicious behavior");
        
        (, status,,,) = reputation.getRunnerStatus(runner1);
        assertEq(uint(status), uint(RunnerReputation.RunnerStatus.Banned));
    }
    
    function testGetRunnersWithPagination() public {
        reputation.registerRunner(runner1, runner1Wallet);
        reputation.registerRunner(runner2, runner2Wallet);
        reputation.registerRunner(runner3, runner3Wallet);
        
        string[] memory firstTwo = reputation.getRunners(0, 2);
        assertEq(firstTwo.length, 2);
        
        string[] memory lastOne = reputation.getRunners(2, 1);
        assertEq(lastOne.length, 1);
    }
} 