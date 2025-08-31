// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IFactory{
    function createOrganisation(address _tokenAddress, string memory _name, string memory _symbol) external;
    function registerEmployee(address employee, address organisation) external;
    function getEmployeeOrganisations() external view returns(address[] memory);
    function getOwnedOrganisations() external view returns(address[] memory);
}