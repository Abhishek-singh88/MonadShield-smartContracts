// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IERC20.sol";
import "./interfaces/IERC721.sol";
import "./interfaces/IAutoRevoker.sol";

/**
 * @title AutoRevoker
 * @dev Automated token approval revocation via delegation
 */
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

    function revokeERC20Approval(
        address smartAccount,
        address token,
        address spender,
        string calldata reason
    ) external override onlyAuthorizedAgent(smartAccount) whenNotPaused {
        uint256 currentAllowance = IERC20(token).allowance(smartAccount, spender);
        require(currentAllowance > 0, "AutoRevoker: No approval exists");

        IERC20(token).approve(spender, 0);

        revocationCount++;
        emit ApprovalRevoked(token, smartAccount, spender, currentAllowance, reason);
    }

    function revokeERC721Approval(
        address smartAccount,
        address nft,
        address spender,
        string calldata reason
    ) external override onlyAuthorizedAgent(smartAccount) whenNotPaused {
        require(
            IERC721(nft).isApprovedForAll(smartAccount, spender),
            "AutoRevoker: No approval exists"
        );

        IERC721(nft).setApprovalForAll(spender, false);

        revocationCount++;
        emit ApprovalRevoked(nft, smartAccount, spender, 0, reason);
    }

    function batchRevokeApprovals(
        address smartAccount,
        address[] calldata tokens,
        address[] calldata spenders,
        bool[] calldata isERC721,
        string[] calldata reasons
    ) external override onlyAuthorizedAgent(smartAccount) whenNotPaused {
        require(
            tokens.length == spenders.length &&
            tokens.length == isERC721.length &&
            tokens.length == reasons.length,
            "AutoRevoker: Array length mismatch"
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            if (isERC721[i]) {
                if (IERC721(tokens[i]).isApprovedForAll(smartAccount, spenders[i])) {
                    IERC721(tokens[i]).setApprovalForAll(spenders[i], false);
                    emit ApprovalRevoked(tokens[i], smartAccount, spenders[i], 0, reasons[i]);
                    revocationCount++;
                }
            } else {
                uint256 allowance = IERC20(tokens[i]).allowance(smartAccount, spenders[i]);
                if (allowance > 0) {
                    IERC20(tokens[i]).approve(spenders[i], 0);
                    emit ApprovalRevoked(tokens[i], smartAccount, spenders[i], allowance, reasons[i]);
                    revocationCount++;
                }
            }
        }
    }

    function emergencyRevoke(
        address smartAccount,
        address token,
        address spender,
        bool isERC721,
        string calldata reason
    ) external onlyOwner {
        if (isERC721) {
            IERC721(token).setApprovalForAll(spender, false);
        } else {
            IERC20(token).approve(spender, 0);
        }
        emit EmergencyRevocation(smartAccount, token, spender, reason);
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

    function recordApproval(
        address owner,
        address token,
        address spender,
        uint256 amount,
        bool isERC721
    ) external onlyOwner {
        approvalTimestamps[owner][spender] = block.timestamp;

        userApprovals[owner].push(ApprovalInfo({
            token: token,
            spender: spender,
            timestamp: block.timestamp,
            amount: amount,
            isERC721: isERC721,
            revoked: false
        }));

        emit ApprovalDetected(owner, token, spender, amount, isERC721);
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

    function getRiskAssessment(address contractAddress)
        external view
        returns (bool isBlacklisted, uint256 riskScore, uint256 maxApprovalTime)
    {
        RiskRule memory rule = riskRules[contractAddress];
        return (rule.isBlacklisted, rule.riskScore, rule.maxApprovalTime);
    }

    function getApprovalHistory(address user)
        external view
        returns (ApprovalInfo[] memory)
    {
        return userApprovals[user];
    }

    function shouldAutoRevoke(address owner, address spender)
        external view
        returns (bool shouldRevoke, string memory reason)
    {
        RiskRule memory rule = riskRules[spender];

        if (rule.isBlacklisted) {
            return (true, "Contract is blacklisted");
        }
        if (rule.riskScore >= HIGH_RISK_THRESHOLD) {
            return (true, "High risk contract detected");
        }
        if (rule.maxApprovalTime > 0) {
            uint256 approvalTime = approvalTimestamps[owner][spender];
            if (approvalTime > 0 && block.timestamp > approvalTime + rule.maxApprovalTime) {
                return (true, "Approval time limit exceeded");
            }
        }
        return (false, "");
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

    function getStats()
        external view
        returns (uint256 totalDelegations, uint256 totalRevocations, bool contractPaused)
    {
        return (delegationCount, revocationCount, paused);
    }
}
