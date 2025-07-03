// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title RunnerReputationProxy
 * @dev Proxy contract for RunnerReputationUpgradeable using ERC1967
 */
contract RunnerReputationProxy is ERC1967Proxy {
    constructor(address _logic, bytes memory _data) ERC1967Proxy(_logic, _data) {}
}
