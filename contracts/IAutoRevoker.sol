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

    function isDelegationActive(address smartAccount) external view returns (bool);

    function getDelegationInfo(address smartAccount) 
        external 
        view 
        returns (address agent, uint256 expiry, bool active);
}
