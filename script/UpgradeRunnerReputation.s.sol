// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/RunnerReputationUpgradeable.sol";

contract UpgradeScript is Script {
    error InvalidPrivateKey();
    error EnvironmentError(string message);

    function setUp() public {}

    function run() external {
        console.log("\n=== Runner Reputation Upgrade ===");

        // Check if we're in CI environment
        bool isCI = _isCI();

        // Get and validate private key and proxy address
        uint256 deployerPrivateKey = _getPrivateKey();
        address proxyAddress = vm.envAddress("RUNNER_REPUTATION_PROXY_ADDRESS");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("\n=== Upgrade Information ===");
        console.log("Deployer:", deployer);
        console.log("Proxy Address:", proxyAddress);
        console.log("Chain ID:", block.chainid);
        console.log("Network:", _getNetworkName());

        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        RunnerReputationUpgradeable newImplementation = new RunnerReputationUpgradeable();
        console.log("\nNew Implementation deployed to:", address(newImplementation));

        // Upgrade the proxy to point to the new implementation
        RunnerReputationUpgradeable proxy = RunnerReputationUpgradeable(proxyAddress);
        proxy.upgradeToAndCall(address(newImplementation), "");

        vm.stopBroadcast();

        console.log("\n=== Upgrade Successful! ===");
        console.log("Proxy at:", proxyAddress);
        console.log("Now points to implementation:", address(newImplementation));

        // Save new implementation address to .env if not in CI
        if (!isCI) {
            _saveImplementationAddress(address(newImplementation));
        }

        // Upgrade verification instructions
        if (block.chainid == 314159) { // Filecoin Calibration
            console.log("\n=== Next Steps ===");
            console.log("1. New implementation address saved to .env");
            console.log("2. To verify new implementation on Blockscout, run:");
            console.log(
                string.concat(
                    "   make verify-calibration-implementation CONTRACT_ADDRESS=",
                    vm.toString(address(newImplementation))
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
                return 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
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

    function _saveImplementationAddress(address implementation) internal {
        string[] memory inputs = new string[](4);
        inputs[0] = "bash";
        inputs[1] = "-c";
        inputs[2] = string.concat(
            "sed -i '' 's/^RUNNER_REPUTATION_IMPLEMENTATION_ADDRESS=.*$/RUNNER_REPUTATION_IMPLEMENTATION_ADDRESS=", 
            vm.toString(implementation), 
            "/' .env"
        );

        try vm.ffi(inputs) {
            console.log("Implementation address saved to .env");
        } catch {
            console.log("Warning: Could not save implementation address to .env");
            console.log("Please manually update the following in your .env file:");
            console.log(string.concat("RUNNER_REPUTATION_IMPLEMENTATION_ADDRESS=", vm.toString(implementation)));
        }
    }
}
