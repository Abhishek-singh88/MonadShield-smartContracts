// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IERC20.sol";
import "./IERC721.sol";
import "./IAutoRevoker.sol";

contract AutoRevoker is IAutoRevoker {
    struct DelegationInfo {
        address delegator;
        address agent;
        uint256 expiry;
        bool active;
        uint256 nonce;
    }

    struct RiskRule {
        address contractAddress;
        bool isBlacklisted;
        uint256 maxApprovalTime;
        uint256 riskScore;
    }

    struct ApprovalInfo {
        address token;
        address spender;
        uint256 timestamp;
        uint256 amount;
        bool isERC721;
        bool revoked;
    }

    mapping(address => DelegationInfo) public delegations;
    mapping(address => RiskRule) public riskRules;
    mapping(address => mapping(address => uint256)) public approvalTimestamps;
    mapping(address => ApprovalInfo[]) public userApprovals;

    address public owner;
    address public emergencyPause;
    bool public paused;

    uint256 public constant MAX_DELEGATION_PERIOD = 365 days;
    uint256 public constant HIGH_RISK_THRESHOLD = 70;
    uint256 public delegationCount;
    uint256 public revocationCount;

    event DelegationGranted(address indexed smartAccount, address indexed agent, uint256 expiry, uint256 nonce);
    event DelegationRevoked(address indexed smartAccount, address indexed agent, uint256 timestamp);
    event ApprovalRevoked(address indexed token, address indexed owner, address indexed spender, uint256 amount, string reason);
    event RiskRuleUpdated(address indexed contractAddress, bool blacklisted, uint256 maxTime, uint256 riskScore);
    event EmergencyRevocation(address indexed smartAccount, address indexed token, address indexed spender, string reason);
    event ApprovalDetected(address indexed owner, address indexed token, address indexed spender, uint256 amount, bool isERC721);

    modifier onlyOwner() {
        require(msg.sender == owner, "AutoRevoker: Not owner");
        _;
    }

    modifier onlyAuthorizedAgent(address smartAccount) {
        DelegationInfo memory delegation = delegations[smartAccount];
        require(delegation.active, "AutoRevoker: No active delegation");
        require(delegation.agent == msg.sender, "AutoRevoker: Not authorized agent");
        require(block.timestamp <= delegation.expiry, "AutoRevoker: Delegation expired");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "AutoRevoker: Contract is paused");
        _;
    }

    modifier validAddress(address addr) {
        require(addr != address(0), "AutoRevoker: Invalid address");
        _;
    }

    constructor() {
        owner = msg.sender;
        emergencyPause = msg.sender;
        paused = false;
    }

    function grantDelegation(
        address agent,
        uint256 duration,
        uint256 nonce,
        bytes calldata signature
    ) external override whenNotPaused validAddress(agent) {
        require(duration > 0 && duration <= MAX_DELEGATION_PERIOD, "AutoRevoker: Invalid duration");
        require(nonce > delegations[msg.sender].nonce, "AutoRevoker: Invalid nonce");

        address smartAccount = msg.sender;
        uint256 expiry = block.timestamp + duration;

        if (delegations[smartAccount].active) {
            _revokeDelegation(smartAccount);
        }

        delegations[smartAccount] = DelegationInfo({
            delegator: smartAccount,
            agent: agent,
            expiry: expiry,
            active: true,
            nonce: nonce
        });

        delegationCount++;
        emit DelegationGranted(smartAccount, agent, expiry, nonce);
    }

    function revokeDelegation() external override {
        _revokeDelegation(msg.sender);
    }

    function _revokeDelegation(address smartAccount) internal {
        DelegationInfo storage delegation = delegations[smartAccount];
        require(delegation.active, "AutoRevoker: No active delegation");

        delegation.active = false;
        emit DelegationRevoked(smartAccount, delegation.agent, block.timestamp);
    }

    function isDelegationActive(address smartAccount) external view override returns (bool) {
        DelegationInfo memory delegation = delegations[smartAccount];
        return delegation.active && block.timestamp <= delegation.expiry;
    }

    function getDelegationInfo(address smartAccount) 
        external view override 
        returns (address agent, uint256 expiry, bool active) 
    {
        DelegationInfo memory delegation = delegations[smartAccount];
        return (delegation.agent, delegation.expiry, delegation.active);
    }

    function getStats() 
        external view 
        returns (uint256 totalDelegations, uint256 totalRevocations, bool contractPaused) 
    {
        return (delegationCount, revocationCount, paused);
    }

    function updateRiskRule(
        address contractAddress,
        bool isBlacklisted,
        uint256 maxApprovalTime,
        uint256 riskScore
    ) external onlyOwner validAddress(contractAddress) {
        require(riskScore <= 100, "AutoRevoker: Invalid risk score");

        riskRules[contractAddress] = RiskRule({
            contractAddress: contractAddress,
            isBlacklisted: isBlacklisted,
            maxApprovalTime: maxApprovalTime,
            riskScore: riskScore
        });

        emit RiskRuleUpdated(contractAddress, isBlacklisted, maxApprovalTime, riskScore);
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unpause() external onlyOwner {
        paused = false;
    }

    function transferOwnership(address newOwner) external onlyOwner validAddress(newOwner) {
        owner = newOwner;
    }
}
