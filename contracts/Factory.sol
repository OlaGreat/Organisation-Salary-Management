// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "./Streamer.sol";
import "../library/Error.sol";
import "../library/Utils.sol";

contract Factory {

  mapping (address => address[]) ownerToOrganisations;
  mapping (address => address[]) employeeToOrganisations;
  mapping (address => bool) isOrganisation;
  address[] allOrganisations;
  constructor(){

  }

  function createOrganisation(address _tokenAddress, string memory _name, string memory _symbol) external{
      Streamer streamer = new Streamer(_tokenAddress, _name, _symbol, msg.sender, address(this));
      ownerToOrganisations[msg.sender].push(address(streamer));
      isOrganisation[address(streamer)] = true;
      allOrganisations.push(address(streamer));
  }

  function getOwnedOrganisations() external view returns(address[] memory){
    return ownerToOrganisations[msg.sender];
  }

  function getEmployeeOrganisations() external view returns(address[] memory){
    return employeeToOrganisations[msg.sender];
  }

  function registerEmployee(address employee, address organisation) external {
    require(isOrganisation[msg.sender], Error.NOT_VALID_ORGANISATION());
    employeeToOrganisations[employee].push(organisation);
}
}
