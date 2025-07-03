// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/RunnerReputationUpgradeable.sol";
import "../src/RunnerReputationProxy.sol";

contract DeployProxyScript is Script {
    error InvalidPrivateKey();
    error EnvironmentError(string message);

    function setUp() public {}

    function run() external {
        console.log("\n=== Runner Reputation Proxy Deployment ===");

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

        // Step 1: Deploy implementation
        RunnerReputationUpgradeable implementation = new RunnerReputationUpgradeable();
        console.log("\nImplementation deployed to:", address(implementation));

        // Step 2: Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(RunnerReputationUpgradeable.initialize.selector);

        // Step 3: Deploy proxy with implementation and initialization
        RunnerReputationProxy proxy = new RunnerReputationProxy(address(implementation), initData);

        vm.stopBroadcast();

        console.log("\n=== Deployment Successful! ===");
        console.log("Implementation deployed to:", address(implementation));
        console.log("Proxy deployed to:", address(proxy));

        // Save addresses to .env if not in CI
        if (!isCI) {
            _saveAddresses(address(proxy), address(implementation));
        }

        // Deployment verification instructions
        if (block.chainid == 314159) { // Filecoin Calibration
            console.log("\n=== Next Steps ===");
            console.log("1. Proxy address saved to .env");
            console.log("2. To verify on Blockscout, run:");
            console.log(
                string.concat(
                    "   make verify-calibration-implementation CONTRACT_ADDRESS=",
                    vm.toString(address(implementation))
                )
            );
            console.log(
                string.concat(
                    "   make verify-calibration-proxy CONTRACT_ADDRESS=",
                    vm.toString(address(proxy))
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

    function _saveAddresses(address proxy, address implementation) internal {
        string[] memory proxyInputs = new string[](4);
        proxyInputs[0] = "bash";
        proxyInputs[1] = "-c";
        proxyInputs[2] = string.concat(
            "sed -i '' 's/^RUNNER_REPUTATION_PROXY_ADDRESS=.*$/RUNNER_REPUTATION_PROXY_ADDRESS=", 
            vm.toString(proxy), 
            "/' .env"
        );

        string[] memory implInputs = new string[](4);
        implInputs[0] = "bash";
        implInputs[1] = "-c";
        implInputs[2] = string.concat(
            "sed -i '' 's/^RUNNER_REPUTATION_IMPLEMENTATION_ADDRESS=.*$/RUNNER_REPUTATION_IMPLEMENTATION_ADDRESS=", 
            vm.toString(implementation), 
            "/' .env"
        );

        try vm.ffi(proxyInputs) {
            console.log("Proxy address saved to .env");
            try vm.ffi(implInputs) {
                console.log("Implementation address saved to .env");
            } catch {
                console.log("Warning: Could not save implementation address to .env");
            }
        } catch {
            console.log("Warning: Could not save addresses to .env");
            console.log("Please manually add the following to your .env file:");
            console.log(string.concat("RUNNER_REPUTATION_PROXY_ADDRESS=", vm.toString(proxy)));
            console.log(string.concat("RUNNER_REPUTATION_IMPLEMENTATION_ADDRESS=", vm.toString(implementation)));
        }
    }
}
