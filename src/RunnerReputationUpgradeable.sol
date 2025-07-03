// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title RunnerReputationUpgradeable
 * @dev Upgradeable smart contract for managing runner reputation with peer monitoring and slashing
 */
contract RunnerReputationUpgradeable is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
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
        Active,
        Warning,
        Banned,
        Suspended
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
        GoodBehavior,
        PoorPerformance,
        SuspiciousActivity,
        MaliciousBehavior,
        Offline,
        ResourceAbuse
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
        uint256 stakedAmount;
        uint256 totalEarnings;
        uint256 totalSlashed;
        uint256 monitoringScore;
        uint256 timesMonitored;
        uint256 timesMonitoring;
    }

    struct MonitoringAssignment {
        string monitorId;
        string targetId;
        uint256 startTime;
        uint256 duration;
        bool isActive;
        bool reportSubmitted;
        MonitoringReportType reportType;
        string evidenceHash;
        uint256 submissionTime;
        bool verified;
        int256 monitorReward;
    }

    struct ReputationEvent {
        ReputationEventType eventType;
        int256 scoreDelta;
        uint256 timestamp;
        string reason;
        address reporter;
        string relatedMonitoringId;
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

    mapping(address => bool) public authorizedReporters;
    mapping(string => RunnerProfile) public runners;
    mapping(address => string) public walletToRunnerId;
    string[] public runnerIds;
    mapping(string => ReputationEvent[]) public reputationEvents;
    mapping(string => MonitoringAssignment) public monitoringAssignments;
    mapping(string => string[]) public runnerMonitoringHistory;
    string[] public activeMonitoringIds;
    uint256 public nextMonitoringId;

    int256 public QUALITY_THRESHOLD;
    int256 public BAN_THRESHOLD;
    int256 public STARTING_SCORE;
    uint256 public MIN_STAKE_AMOUNT;
    uint256 public MONITORING_DURATION;
    uint256 public MONITORING_REWARD;
    uint256 public SLASHING_PERCENTAGE;

    mapping(string => bool) public permanentBans;
    uint256 public BAN_DURATION;
    NetworkStats public networkStats;
    uint256 private randomSeed;

    // ============ MODIFIERS ============

    modifier onlyAuthorized() {
        require(
            authorizedReporters[msg.sender] || msg.sender == owner(),
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

    // ============ CONSTRUCTOR & INITIALIZER ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        authorizedReporters[msg.sender] = true;
        randomSeed = block.timestamp;

        QUALITY_THRESHOLD = 500;
        BAN_THRESHOLD = -100;
        STARTING_SCORE = 500;
        MIN_STAKE_AMOUNT = 100 * 10 ** 18;
        MONITORING_DURATION = 24 hours;
        MONITORING_REWARD = 10 * 10 ** 18;
        SLASHING_PERCENTAGE = 20;
        BAN_DURATION = 30 days;

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

    // ============ UPGRADE AUTHORIZATION ============

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    // ============ STAKING FUNCTIONS ============

    function depositStake(
        string memory runnerId,
        uint256 amount
    ) external onlyAuthorized {
        require(amount > 0, "Amount must be greater than 0");

        runners[runnerId].stakedAmount += amount;
        networkStats.totalStakedAmount += amount;

        emit StakeDeposited(runnerId, runners[runnerId].walletAddress, amount);
    }

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

        reputationEvents[runnerId].push(
            ReputationEvent({
                eventType: ReputationEventType.Slashing,
                scoreDelta: -100,
                timestamp: block.timestamp,
                reason: reason,
                reporter: msg.sender,
                relatedMonitoringId: ""
            })
        );

        runner.reputationScore -= 100;

        emit SlashingExecuted(
            runnerId,
            runner.walletAddress,
            slashedAmount,
            reason
        );

        return slashedAmount;
    }

    // ============ RUNNER MANAGEMENT ============

    function registerRunner(
        string memory runnerId,
        address walletAddress
    ) external onlyAuthorized {
        require(bytes(runnerId).length > 0, "Runner ID cannot be empty");
        require(walletAddress != address(0), "Invalid wallet address");
        require(
            bytes(runners[runnerId].runnerId).length == 0,
            "Runner already exists"
        );
        require(
            bytes(walletToRunnerId[walletAddress]).length == 0,
            "Wallet already associated with a runner"
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
            monitoringScore: uint256(STARTING_SCORE),
            timesMonitored: 0,
            timesMonitoring: 0
        });

        walletToRunnerId[walletAddress] = runnerId;
        runnerIds.push(runnerId);

        networkStats.totalRunners++;
        networkStats.activeRunners++;

        emit RunnerRegistered(runnerId, walletAddress);
    }

    function updateReputation(
        string memory runnerId,
        int256 scoreDelta,
        ReputationEventType eventType,
        string memory reason
    ) external onlyAuthorized runnerExists(runnerId) {
        RunnerProfile storage runner = runners[runnerId];
        int256 oldScore = runner.reputationScore;
        runner.reputationScore += scoreDelta;

        runner.lastActiveAt = block.timestamp;

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

        _updateRunnerStatus(runnerId);
        _updateNetworkStats();

        emit ReputationUpdated(
            runnerId,
            oldScore,
            runner.reputationScore,
            reason
        );
    }

    function getRunnerProfile(
        string memory runnerId
    ) external view returns (RunnerProfile memory) {
        return runners[runnerId];
    }

    function getNetworkStats() external view returns (NetworkStats memory) {
        return networkStats;
    }

    // ============ INTERNAL FUNCTIONS ============

    function _updateRunnerStatus(string memory runnerId) internal {
        RunnerProfile storage runner = runners[runnerId];

        if (runner.reputationScore <= BAN_THRESHOLD) {
            if (runner.status != RunnerStatus.Banned) {
                runner.status = RunnerStatus.Banned;
                runner.bannedAt = block.timestamp;
                runner.banReason = "Reputation below ban threshold";
                networkStats.bannedRunners++;
                networkStats.activeRunners--;
                emit RunnerBanned(
                    runnerId,
                    runner.walletAddress,
                    runner.banReason
                );
            }
        } else if (runner.reputationScore < QUALITY_THRESHOLD) {
            if (runner.status == RunnerStatus.Active) {
                runner.status = RunnerStatus.Warning;
            }
        } else {
            if (
                runner.status == RunnerStatus.Warning ||
                (runner.status == RunnerStatus.Banned &&
                    !permanentBans[runnerId])
            ) {
                runner.status = RunnerStatus.Active;
                if (runner.bannedAt > 0) {
                    networkStats.bannedRunners--;
                    networkStats.activeRunners++;
                    runner.bannedAt = 0;
                    runner.banReason = "";
                    emit RunnerUnbanned(runnerId, runner.walletAddress);
                }
            }
        }
    }

    function _updateNetworkStats() internal {
        int256 totalScore = 0;
        uint256 activeCount = 0;
        uint256 bannedCount = 0;

        for (uint256 i = 0; i < runnerIds.length; i++) {
            RunnerProfile memory runner = runners[runnerIds[i]];
            totalScore += runner.reputationScore;

            if (
                runner.status == RunnerStatus.Active ||
                runner.status == RunnerStatus.Warning
            ) {
                activeCount++;
            } else if (runner.status == RunnerStatus.Banned) {
                bannedCount++;
            }
        }

        networkStats.activeRunners = activeCount;
        networkStats.bannedRunners = bannedCount;

        if (runnerIds.length > 0) {
            networkStats.averageReputation =
                totalScore /
                int256(runnerIds.length);
        }
    }

    // ============ ADMIN FUNCTIONS ============

    function addAuthorizedReporter(address reporter) external onlyOwner {
        authorizedReporters[reporter] = true;
    }

    function removeAuthorizedReporter(address reporter) external onlyOwner {
        authorizedReporters[reporter] = false;
    }

    function updateQualityThreshold(int256 newThreshold) external onlyOwner {
        int256 oldThreshold = QUALITY_THRESHOLD;
        QUALITY_THRESHOLD = newThreshold;
        emit QualityThresholdUpdated(oldThreshold, newThreshold);
    }

    function updateBanThreshold(int256 newThreshold) external onlyOwner {
        int256 oldThreshold = BAN_THRESHOLD;
        BAN_THRESHOLD = newThreshold;
        emit BanThresholdUpdated(oldThreshold, newThreshold);
    }
}
