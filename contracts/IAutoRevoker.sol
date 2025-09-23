// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IAutoRevoker {
    function grantDelegation(
        address agent,
        uint256 duration,
        uint256 nonce,
        bytes calldata signature
    ) external;

    function revokeDelegation() external;

    function revokeERC20Approval(
        address smartAccount,
        address token,
        address spender,
        string calldata reason
    ) external;

    function revokeERC721Approval(
        address smartAccount,
        address nft,
        address spender,
        string calldata reason
    ) external;

    function batchRevokeApprovals(
        address smartAccount,
        address[] calldata tokens,
        address[] calldata spenders,
        bool[] calldata isERC721,
        string[] calldata reasons
    ) external;

    function isDelegationActive(address smartAccount) external view returns (bool);

    function getDelegationInfo(address smartAccount)
        external
        view
        returns (address agent, uint256 expiry, bool active);
}
