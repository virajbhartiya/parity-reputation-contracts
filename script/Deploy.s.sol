// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/RunnerReputation.sol";

contract DeployRunnerReputation is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the RunnerReputation contract
        RunnerReputation reputationContract = new RunnerReputation();
        
        console.log("RunnerReputation deployed to:", address(reputationContract));
        console.log("Contract owner:", reputationContract.owner());
        console.log("Quality threshold:", reputationContract.QUALITY_THRESHOLD());
        console.log("Ban threshold:", reputationContract.BAN_THRESHOLD());
        console.log("Starting score:", reputationContract.STARTING_SCORE());
        
        vm.stopBroadcast();
        
        // Save deployment information
        string memory deploymentInfo = string(abi.encodePacked(
            "{\n",
            '  "contract_address": "', vm.toString(address(reputationContract)), '",\n',
            '  "network": "filecoin_calibration",\n',
            '  "deployer": "', vm.toString(vm.addr(deployerPrivateKey)), '",\n',
            '  "quality_threshold": ', vm.toString(reputationContract.QUALITY_THRESHOLD()), ',\n',
            '  "ban_threshold": ', vm.toString(reputationContract.BAN_THRESHOLD()), ',\n',
            '  "starting_score": ', vm.toString(reputationContract.STARTING_SCORE()), '\n',
            "}"
        ));
        
        vm.writeFile("deployment.json", deploymentInfo);
        console.log("Deployment info saved to deployment.json");
    }
} 