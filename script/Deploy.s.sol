// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/RunnerReputation.sol";

contract DeployScript is Script {
    error InvalidPrivateKey();
    error EnvironmentError(string message);

    function setUp() public {}

    function run() external {
        console.log("\n=== Runner Reputation Deployment ===");

        // Check if we're in CI environment
        bool isCI = _isCI();

        // Get and validate private key
        uint256 deployerPrivateKey = _getPrivateKey();
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n=== Deployment Information ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Network:", _getNetworkName());

        vm.startBroadcast(deployerPrivateKey);

        // Deploy with high gas limit (configured in foundry.toml)
        RunnerReputation runnerReputation = new RunnerReputation();

        vm.stopBroadcast();

        console.log("\n=== Deployment Successful! ===");
        console.log("RunnerReputation deployed to:", address(runnerReputation));

        // Save address to .env if not in CI
        if (!isCI) {
            _saveAddress(address(runnerReputation));
        }

        // Verify deployment
        console.log("\n=== Contract Verification ===");
        console.log("Contract owner:", runnerReputation.owner());
        console.log("Starting score:", runnerReputation.STARTING_SCORE());
        console.log("Ban threshold:", runnerReputation.BAN_THRESHOLD());
        console.log("Quality threshold:", runnerReputation.QUALITY_THRESHOLD());

        // Deployment verification instructions
        if (block.chainid == 314159) {
            // Filecoin Calibration
            console.log("\n=== Next Steps ===");
            console.log("1. Contract address saved to .env");
            console.log("2. To verify on Blockscout, run:");
            console.log(
                string.concat(
                    "   make verify-calibration CONTRACT_ADDRESS=",
                    vm.toString(address(runnerReputation))
                )
            );
        }
    }

    function _isCI() internal view returns (bool) {
        try vm.envBool("CI") returns (bool ci) {
            return ci;
        } catch {
            return false;
        }
    }

    function _getPrivateKey() internal view returns (uint256) {
        bool isCI = _isCI();

        try vm.envUint("DEPLOYER_PRIVATE_KEY") returns (uint256 key) {
            if (key == 0) revert InvalidPrivateKey();
            return key;
        } catch {
            // Use default key for local testing or CI
            if (block.chainid == 31337 || isCI) {
                return
                    0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
            }
            revert InvalidPrivateKey();
        }
    }

    function _getNetworkName() internal view returns (string memory) {
        if (block.chainid == 314159) return "Filecoin Calibration";
        if (block.chainid == 314) return "Filecoin Mainnet";
        if (block.chainid == 31337) return "Local";
        return "Unknown";
    }

    function _saveAddress(address contractAddress) internal {
        string[] memory inputs = new string[](4);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = string.concat(
            "sed -i '' 's/^RUNNER_REPUTATION_CONTRACT_ADDRESS=.*$/RUNNER_REPUTATION_CONTRACT_ADDRESS=",
            vm.toString(contractAddress),
            "/' .env"
        );

        try vm.ffi(inputs) {
            console.log("Contract address saved to .env");
        } catch {
            console.log("Warning: Could not save address to .env");
            console.log("Please manually add the following to your .env file:");
            console.log(
                string.concat(
                    "RUNNER_REPUTATION_CONTRACT_ADDRESS=",
                    vm.toString(contractAddress)
                )
            );
        }
    }
}
