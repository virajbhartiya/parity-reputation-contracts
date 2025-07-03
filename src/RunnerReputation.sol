// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console.sol";

/**
 * @title RunnerReputation
 * @dev Smart contract for managing runner reputation with peer monitoring and slashing
 */
contract RunnerReputation {
    // ============ EVENTS ============

    event RunnerRegistered(
        string indexed runnerId,
        address indexed walletAddress
    );
    event ReputationUpdated(
        string indexed runnerId,
        int256 oldScore,
        int256 newScore,
        string reason
    );
    event RunnerBanned(
        string indexed runnerId,
        address indexed walletAddress,
        string reason
    );
    event RunnerUnbanned(
        string indexed runnerId,
        address indexed walletAddress
    );
    event IPFSHashUpdated(string indexed runnerId, string ipfsHash);
    event QualityThresholdUpdated(int256 oldThreshold, int256 newThreshold);
    event BanThresholdUpdated(int256 oldThreshold, int256 newThreshold);
    event MonitoringAssigned(
        string indexed monitorId,
        string indexed targetId,
        uint256 duration
    );
    event MonitoringReportSubmitted(
        string indexed monitorId,
        string indexed targetId,
        uint8 reportType,
        string evidence
    );
    event SlashingExecuted(
        string indexed runnerId,
        address indexed wallet,
        uint256 amount,
        string reason
    );
    event StakeDeposited(
        string indexed runnerId,
        address indexed wallet,
        uint256 amount
    );
    event StakeWithdrawn(
        string indexed runnerId,
        address indexed wallet,
        uint256 amount
    );

    // ============ ENUMS ============

    enum RunnerStatus {
        Active, // Good standing, can participate
        Warning, // Low reputation but not banned
        Banned, // Banned from network participation
        Suspended // Temporarily suspended pending review
    }

    enum ReputationEventType {
        TaskCompleted,
        TaskFailed,
        HighQuality,
        PoorQuality,
        FastExecution,
        SlowExecution,
        Malicious,
        Penalty,
        Bonus,
        Manual,
        PeerReport,
        MonitoringReward,
        Slashing
    }

    enum MonitoringReportType {
        GoodBehavior, // Positive monitoring report
        PoorPerformance, // Consistent failures or slow responses
        SuspiciousActivity, // Unusual patterns
        MaliciousBehavior, // Clear malicious intent
        Offline, // Runner appears offline/unresponsive
        ResourceAbuse // Hogging resources or spamming
    }

    // ============ STRUCTS ============

    struct RunnerProfile {
        string runnerId;
        address walletAddress;
        int256 reputationScore;
        RunnerStatus status;
        uint256 totalTasks;
        uint256 successfulTasks;
        uint256 failedTasks;
        uint256 maliciousReports;
        uint256 joinedAt;
        uint256 lastActiveAt;
        uint256 bannedAt;
        string banReason;
        string ipfsDataHash;
        uint256 stakedAmount; // Amount staked for participation
        uint256 totalEarnings; // Total earnings from tasks + monitoring
        uint256 totalSlashed; // Total amount slashed for bad behavior
        uint256 monitoringScore; // Score as a monitor (accuracy of reports)
        uint256 timesMonitored; // How many times this runner was monitored
        uint256 timesMonitoring; // How many times this runner monitored others
    }

    struct MonitoringAssignment {
        string monitorId;
        string targetId;
        uint256 startTime;
        uint256 duration;
        bool isActive;
        bool reportSubmitted;
        MonitoringReportType reportType;
        string evidenceHash; // IPFS hash of monitoring evidence
        uint256 submissionTime;
        bool verified; // Whether the monitoring report was verified
        int256 monitorReward; // Reward/penalty for the monitor
    }

    struct ReputationEvent {
        ReputationEventType eventType;
        int256 scoreDelta;
        uint256 timestamp;
        string reason;
        address reporter;
        string relatedMonitoringId; // ID of related monitoring assignment
    }

    struct NetworkStats {
        uint256 totalRunners;
        uint256 activeRunners;
        uint256 bannedRunners;
        int256 averageReputation;
        uint256 totalTasks;
        uint256 activeMonitoringAssignments;
        uint256 totalSlashedAmount;
        uint256 totalStakedAmount;
    }

    // ============ STATE VARIABLES ============

    address public owner;
    mapping(address => bool) public authorizedReporters;

    // Runner data
    mapping(string => RunnerProfile) public runners;
    mapping(address => string) public walletToRunnerId;
    string[] public runnerIds;

    // Reputation events history
    mapping(string => ReputationEvent[]) public reputationEvents;

    // Monitoring system
    mapping(string => MonitoringAssignment) public monitoringAssignments;
    mapping(string => string[]) public runnerMonitoringHistory; // runner -> assignment IDs
    string[] public activeMonitoringIds;
    uint256 public nextMonitoringId;

    // Thresholds and parameters
    int256 public QUALITY_THRESHOLD = 500;
    int256 public BAN_THRESHOLD = -100;
    int256 public STARTING_SCORE = 500;
    uint256 public MIN_STAKE_AMOUNT = 100 * 10 ** 18; // 100 tokens minimum stake
    uint256 public MONITORING_DURATION = 24 hours; // Default monitoring period
    uint256 public MONITORING_REWARD = 10 * 10 ** 18; // Reward for good monitoring
    uint256 public SLASHING_PERCENTAGE = 20; // 20% of stake slashed for malicious behavior

    // Ban management
    mapping(string => bool) public permanentBans;
    uint256 public BAN_DURATION = 30 days;

    // Network statistics
    NetworkStats public networkStats;

    // Random seed for monitoring assignments
    uint256 private randomSeed;

    // ============ MODIFIERS ============

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyAuthorized() {
        require(
            authorizedReporters[msg.sender] || msg.sender == owner,
            "Not authorized"
        );
        _;
    }

    modifier runnerExists(string memory runnerId) {
        require(
            bytes(runners[runnerId].runnerId).length > 0,
            "Runner does not exist"
        );
        _;
    }

    modifier notBanned(string memory runnerId) {
        require(
            runners[runnerId].status != RunnerStatus.Banned,
            "Runner is banned"
        );
        _;
    }

    modifier hasMinimumStake(string memory runnerId) {
        require(
            runners[runnerId].stakedAmount >= MIN_STAKE_AMOUNT,
            "Insufficient stake"
        );
        _;
    }

    // ============ CONSTRUCTOR ============

    constructor() {
        owner = msg.sender;
        authorizedReporters[msg.sender] = true;
        randomSeed = block.timestamp;

        networkStats = NetworkStats({
            totalRunners: 0,
            activeRunners: 0,
            bannedRunners: 0,
            averageReputation: STARTING_SCORE,
            totalTasks: 0,
            activeMonitoringAssignments: 0,
            totalSlashedAmount: 0,
            totalStakedAmount: 0
        });
    }

    // ============ STAKING FUNCTIONS ============

    /**
     * @dev Deposit stake for a runner (called by wallet contract)
     */
    function depositStake(
        string memory runnerId,
        uint256 amount
    ) external onlyAuthorized {
        require(amount > 0, "Amount must be greater than 0");

        runners[runnerId].stakedAmount += amount;
        networkStats.totalStakedAmount += amount;

        emit StakeDeposited(runnerId, runners[runnerId].walletAddress, amount);
    }

    /**
     * @dev Withdraw stake for a runner (with penalties if applicable)
     */
    function withdrawStake(
        string memory runnerId,
        uint256 amount
    ) external onlyAuthorized runnerExists(runnerId) {
        RunnerProfile storage runner = runners[runnerId];
        require(runner.stakedAmount >= amount, "Insufficient staked amount");
        require(
            runner.status != RunnerStatus.Banned,
            "Cannot withdraw while banned"
        );

        runner.stakedAmount -= amount;
        networkStats.totalStakedAmount -= amount;

        emit StakeWithdrawn(runnerId, runner.walletAddress, amount);
    }

    /**
     * @dev Slash stake for malicious behavior
     */
    function slashStake(
        string memory runnerId,
        string memory reason
    )
        external
        onlyAuthorized
        runnerExists(runnerId)
        returns (uint256 slashedAmount)
    {
        RunnerProfile storage runner = runners[runnerId];

        slashedAmount = (runner.stakedAmount * SLASHING_PERCENTAGE) / 100;
        if (slashedAmount > runner.stakedAmount) {
            slashedAmount = runner.stakedAmount;
        }

        runner.stakedAmount -= slashedAmount;
        runner.totalSlashed += slashedAmount;
        networkStats.totalStakedAmount -= slashedAmount;
        networkStats.totalSlashedAmount += slashedAmount;

        // Log slashing event
        reputationEvents[runnerId].push(
            ReputationEvent({
                eventType: ReputationEventType.Slashing,
                scoreDelta: -100, // Heavy reputation penalty
                timestamp: block.timestamp,
                reason: reason,
                reporter: msg.sender,
                relatedMonitoringId: ""
            })
        );

        // Apply reputation penalty
        runner.reputationScore -= 100;

        emit SlashingExecuted(
            runnerId,
            runner.walletAddress,
            slashedAmount,
            reason
        );

        return slashedAmount;
    }

    // ============ MONITORING FUNCTIONS ============

    /**
     * @dev Assign random monitoring pairs
     */
    function assignRandomMonitoring() external onlyAuthorized {
        uint256 activeRunnerCount = 0;
        string[] memory activeRunnersList = new string[](runnerIds.length);

        // Get list of active runners with sufficient stake
        for (uint256 i = 0; i < runnerIds.length; i++) {
            RunnerProfile memory runner = runners[runnerIds[i]];
            if (
                runner.status == RunnerStatus.Active &&
                runner.stakedAmount >= MIN_STAKE_AMOUNT
            ) {
                activeRunnersList[activeRunnerCount] = runnerIds[i];
                activeRunnerCount++;
            }
        }

        require(
            activeRunnerCount >= 2,
            "Need at least 2 active runners for monitoring"
        );

        // Create monitoring pairs
        uint256 monitoringPairs = activeRunnerCount / 2;

        // Simple pairing approach
        uint256 pairsCreated = 0;
        for (
            uint256 i = 0;
            i < activeRunnerCount && pairsCreated < monitoringPairs;
            i += 2
        ) {
            if (i + 1 >= activeRunnerCount) break;

            string memory monitorId = activeRunnersList[i];
            string memory targetId = activeRunnersList[i + 1];

            // Create monitoring assignment
            string memory assignmentId = string(
                abi.encodePacked("monitor-", _uint2str(nextMonitoringId++))
            );

            monitoringAssignments[assignmentId] = MonitoringAssignment({
                monitorId: monitorId,
                targetId: targetId,
                startTime: block.timestamp,
                duration: MONITORING_DURATION,
                isActive: true,
                reportSubmitted: false,
                reportType: MonitoringReportType.GoodBehavior,
                evidenceHash: "",
                submissionTime: 0,
                verified: false,
                monitorReward: 0
            });

            activeMonitoringIds.push(assignmentId);
            runnerMonitoringHistory[monitorId].push(assignmentId);

            runners[monitorId].timesMonitoring++;
            runners[targetId].timesMonitored++;

            networkStats.activeMonitoringAssignments++;

            emit MonitoringAssigned(monitorId, targetId, MONITORING_DURATION);

            pairsCreated++;
        }
    }

    /**
     * @dev Submit monitoring report
     */
    function submitMonitoringReport(
        string memory assignmentId,
        MonitoringReportType reportType,
        string memory evidenceHash
    ) external onlyAuthorized {
        MonitoringAssignment storage assignment = monitoringAssignments[
            assignmentId
        ];
        require(assignment.isActive, "Assignment not active");
        require(!assignment.reportSubmitted, "Report already submitted");
        require(
            block.timestamp <= assignment.startTime + assignment.duration,
            "Monitoring period expired"
        );

        assignment.reportType = reportType;
        assignment.evidenceHash = evidenceHash;
        assignment.submissionTime = block.timestamp;
        assignment.reportSubmitted = true;

        emit MonitoringReportSubmitted(
            assignment.monitorId,
            assignment.targetId,
            uint8(reportType),
            evidenceHash
        );

        // Process the report immediately for now (in production, might want delayed verification)
        _processMonitoringReport(assignmentId);
    }

    /**
     * @dev Process monitoring report and update reputations
     */
    function _processMonitoringReport(string memory assignmentId) internal {
        MonitoringAssignment storage assignment = monitoringAssignments[
            assignmentId
        ];
        assignment.verified = true;
        assignment.isActive = false;

        RunnerProfile storage monitor = runners[assignment.monitorId];
        RunnerProfile storage target = runners[assignment.targetId];

        int256 targetScoreDelta = 0;
        int256 monitorReward = int256(MONITORING_REWARD);
        string memory reason = "";

        // Determine reputation changes based on report type
        if (assignment.reportType == MonitoringReportType.GoodBehavior) {
            targetScoreDelta = 5; // Small bonus for good behavior
            reason = "Positive monitoring report";
        } else if (
            assignment.reportType == MonitoringReportType.PoorPerformance
        ) {
            targetScoreDelta = -10;
            reason = "Poor performance reported by peer monitor";
        } else if (
            assignment.reportType == MonitoringReportType.SuspiciousActivity
        ) {
            targetScoreDelta = -20;
            reason = "Suspicious activity reported by peer monitor";
        } else if (
            assignment.reportType == MonitoringReportType.MaliciousBehavior
        ) {
            targetScoreDelta = -50;
            reason = "Malicious behavior reported by peer monitor";
            // Trigger slashing for malicious behavior - inline implementation
            RunnerProfile storage targetRunner = runners[assignment.targetId];
            uint256 slashedAmount = (targetRunner.stakedAmount *
                SLASHING_PERCENTAGE) / 100;
            if (slashedAmount > targetRunner.stakedAmount) {
                slashedAmount = targetRunner.stakedAmount;
            }

            if (slashedAmount > 0) {
                targetRunner.stakedAmount -= slashedAmount;
                targetRunner.totalSlashed += slashedAmount;
                networkStats.totalStakedAmount -= slashedAmount;
                networkStats.totalSlashedAmount += slashedAmount;

                // Additional slashing penalty
                targetScoreDelta -= 100;

                emit SlashingExecuted(
                    assignment.targetId,
                    targetRunner.walletAddress,
                    slashedAmount,
                    reason
                );
            }
        } else if (assignment.reportType == MonitoringReportType.Offline) {
            targetScoreDelta = -5;
            reason = "Runner offline during monitoring period";
        } else if (
            assignment.reportType == MonitoringReportType.ResourceAbuse
        ) {
            targetScoreDelta = -30;
            reason = "Resource abuse reported by peer monitor";
        }

        // Update target reputation
        if (targetScoreDelta != 0) {
            target.reputationScore += targetScoreDelta;

            reputationEvents[assignment.targetId].push(
                ReputationEvent({
                    eventType: ReputationEventType.PeerReport,
                    scoreDelta: targetScoreDelta,
                    timestamp: block.timestamp,
                    reason: reason,
                    reporter: address(0), // Peer report
                    relatedMonitoringId: assignmentId
                })
            );

            emit ReputationUpdated(
                assignment.targetId,
                target.reputationScore - targetScoreDelta,
                target.reputationScore,
                reason
            );
        }

        // Reward the monitor
        monitor.totalEarnings += uint256(monitorReward);
        monitor.monitoringScore += 10; // Increase monitoring accuracy score
        assignment.monitorReward = monitorReward;

        reputationEvents[assignment.monitorId].push(
            ReputationEvent({
                eventType: ReputationEventType.MonitoringReward,
                scoreDelta: 5, // Small reputation bonus for monitoring
                timestamp: block.timestamp,
                reason: "Monitoring service completed",
                reporter: address(0),
                relatedMonitoringId: assignmentId
            })
        );

        monitor.reputationScore += 5;

        // Check if target should be banned
        if (
            target.reputationScore <= BAN_THRESHOLD &&
            target.status != RunnerStatus.Banned
        ) {
            _banRunner(
                assignment.targetId,
                "Reputation dropped below threshold due to peer monitoring"
            );
        }

        networkStats.activeMonitoringAssignments--;
        _updateNetworkStats();
    }

    // ============ CORE REPUTATION FUNCTIONS ============

    function updateReputation(
        string memory runnerId,
        ReputationEventType eventType,
        int256 scoreDelta,
        string memory reason
    ) external onlyAuthorized runnerExists(runnerId) {
        RunnerProfile storage runner = runners[runnerId];
        int256 oldScore = runner.reputationScore;

        runner.reputationScore += scoreDelta;
        runner.lastActiveAt = block.timestamp;

        if (eventType == ReputationEventType.TaskCompleted) {
            runner.totalTasks++;
            runner.successfulTasks++;
            networkStats.totalTasks++;
        } else if (eventType == ReputationEventType.TaskFailed) {
            runner.totalTasks++;
            runner.failedTasks++;
            networkStats.totalTasks++;
        } else if (eventType == ReputationEventType.Malicious) {
            runner.maliciousReports++;
        }

        reputationEvents[runnerId].push(
            ReputationEvent({
                eventType: eventType,
                scoreDelta: scoreDelta,
                timestamp: block.timestamp,
                reason: reason,
                reporter: msg.sender,
                relatedMonitoringId: ""
            })
        );

        if (
            runner.reputationScore <= BAN_THRESHOLD &&
            runner.status != RunnerStatus.Banned
        ) {
            _banRunner(runnerId, "Reputation score below ban threshold");
        } else if (
            runner.reputationScore > QUALITY_THRESHOLD &&
            runner.status == RunnerStatus.Warning
        ) {
            runner.status = RunnerStatus.Active;
            networkStats.activeRunners++;
        } else if (
            runner.reputationScore < QUALITY_THRESHOLD &&
            runner.reputationScore > BAN_THRESHOLD
        ) {
            if (runner.status == RunnerStatus.Active) {
                runner.status = RunnerStatus.Warning;
            }
        }

        _updateNetworkStats();

        emit ReputationUpdated(
            runnerId,
            oldScore,
            runner.reputationScore,
            reason
        );
    }

    function banRunner(
        string memory runnerId,
        string memory reason
    ) external onlyAuthorized runnerExists(runnerId) {
        _banRunner(runnerId, reason);
    }

    function registerRunner(
        string memory runnerId,
        address walletAddress
    ) external onlyAuthorized {
        require(
            bytes(runners[runnerId].runnerId).length == 0,
            "Runner already exists"
        );
        require(
            bytes(walletToRunnerId[walletAddress]).length == 0,
            "Wallet already registered"
        );

        runners[runnerId] = RunnerProfile({
            runnerId: runnerId,
            walletAddress: walletAddress,
            reputationScore: STARTING_SCORE,
            status: RunnerStatus.Active,
            totalTasks: 0,
            successfulTasks: 0,
            failedTasks: 0,
            maliciousReports: 0,
            joinedAt: block.timestamp,
            lastActiveAt: block.timestamp,
            bannedAt: 0,
            banReason: "",
            ipfsDataHash: "",
            stakedAmount: 0,
            totalEarnings: 0,
            totalSlashed: 0,
            monitoringScore: 100, // Start with good monitoring score
            timesMonitored: 0,
            timesMonitoring: 0
        });

        walletToRunnerId[walletAddress] = runnerId;
        runnerIds.push(runnerId);

        networkStats.totalRunners++;
        networkStats.activeRunners++;

        emit RunnerRegistered(runnerId, walletAddress);
    }

    // ============ VIEW FUNCTIONS ============

    function getMonitoringAssignment(
        string memory assignmentId
    ) external view returns (MonitoringAssignment memory) {
        return monitoringAssignments[assignmentId];
    }

    function getRunnerMonitoringHistory(
        string memory runnerId
    ) external view returns (string[] memory) {
        return runnerMonitoringHistory[runnerId];
    }

    function getActiveMonitoringAssignments()
        external
        view
        returns (string[] memory)
    {
        return activeMonitoringIds;
    }

    function isRunnerEligible(
        string memory runnerId
    ) external view returns (bool) {
        if (bytes(runners[runnerId].runnerId).length == 0) return false;

        RunnerProfile memory runner = runners[runnerId];
        return
            (runner.status == RunnerStatus.Active ||
                runner.status == RunnerStatus.Warning) &&
            runner.stakedAmount >= MIN_STAKE_AMOUNT;
    }

    function getRunnerStatus(
        string memory runnerId
    )
        external
        view
        runnerExists(runnerId)
        returns (
            int256 reputationScore,
            RunnerStatus status,
            uint256 totalTasks,
            uint256 successRate,
            bool isBanned
        )
    {
        RunnerProfile memory runner = runners[runnerId];

        uint256 successRatePercent = runner.totalTasks > 0
            ? (runner.successfulTasks * 100) / runner.totalTasks
            : 0;

        return (
            runner.reputationScore,
            runner.status,
            runner.totalTasks,
            successRatePercent,
            runner.status == RunnerStatus.Banned
        );
    }

    function getRunnerProfile(
        string memory runnerId
    ) external view runnerExists(runnerId) returns (RunnerProfile memory) {
        return runners[runnerId];
    }

    function getReputationEvents(
        string memory runnerId
    ) external view runnerExists(runnerId) returns (ReputationEvent[] memory) {
        return reputationEvents[runnerId];
    }

    function getNetworkStats() external view returns (NetworkStats memory) {
        return networkStats;
    }

    function getRunners(
        uint256 offset,
        uint256 limit
    ) external view returns (string[] memory) {
        require(offset < runnerIds.length, "Offset out of bounds");

        uint256 end = offset + limit;
        if (end > runnerIds.length) {
            end = runnerIds.length;
        }

        string[] memory result = new string[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = runnerIds[i];
        }

        return result;
    }

    function getTopRunners(
        uint256 limit
    )
        external
        view
        returns (string[] memory topRunners, int256[] memory scores)
    {
        require(limit <= runnerIds.length, "Limit exceeds total runners");

        string[] memory sortedRunners = new string[](runnerIds.length);
        int256[] memory sortedScores = new int256[](runnerIds.length);

        for (uint256 i = 0; i < runnerIds.length; i++) {
            sortedRunners[i] = runnerIds[i];
            sortedScores[i] = runners[runnerIds[i]].reputationScore;
        }

        for (uint256 i = 0; i < runnerIds.length - 1; i++) {
            for (uint256 j = 0; j < runnerIds.length - i - 1; j++) {
                if (sortedScores[j] < sortedScores[j + 1]) {
                    int256 tempScore = sortedScores[j];
                    string memory tempRunner = sortedRunners[j];
                    sortedScores[j] = sortedScores[j + 1];
                    sortedRunners[j] = sortedRunners[j + 1];
                    sortedScores[j + 1] = tempScore;
                    sortedRunners[j + 1] = tempRunner;
                }
            }
        }

        topRunners = new string[](limit);
        scores = new int256[](limit);
        for (uint256 i = 0; i < limit; i++) {
            topRunners[i] = sortedRunners[i];
            scores[i] = sortedScores[i];
        }

        return (topRunners, scores);
    }

    function isRunnerBanned(
        string memory runnerId
    ) external view returns (bool) {
        if (bytes(runners[runnerId].runnerId).length == 0) return false;
        return runners[runnerId].status == RunnerStatus.Banned;
    }

    // ============ HELPER FUNCTIONS ============

    function _getRandomNumber(uint256 max) internal returns (uint256) {
        if (max == 0) return 0;
        randomSeed = uint256(
            keccak256(
                abi.encodePacked(block.timestamp, block.prevrandao, randomSeed)
            )
        );
        return randomSeed % max;
    }

    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function _removeFromArray(
        string[] memory arr,
        uint256 length,
        uint256 index
    ) internal pure {
        for (uint256 i = index; i < length - 1; i++) {
            arr[i] = arr[i + 1];
        }
    }

    function _updateNetworkStats() internal {
        if (networkStats.totalRunners > 0) {
            int256 totalReputation = 0;
            for (uint256 i = 0; i < runnerIds.length; i++) {
                totalReputation += runners[runnerIds[i]].reputationScore;
            }
            networkStats.averageReputation =
                totalReputation /
                int256(networkStats.totalRunners);
        }
    }

    function _banRunner(string memory runnerId, string memory reason) internal {
        RunnerProfile storage runner = runners[runnerId];

        if (runner.status != RunnerStatus.Banned) {
            runner.status = RunnerStatus.Banned;
            runner.bannedAt = block.timestamp;
            runner.banReason = reason;

            networkStats.bannedRunners++;
            if (networkStats.activeRunners > 0) {
                networkStats.activeRunners--;
            }

            emit RunnerBanned(runnerId, runner.walletAddress, reason);
        }
    }
}
