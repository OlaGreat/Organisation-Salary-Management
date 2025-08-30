// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;
import "./Streamer.sol";

contract Factory {

  mapping (address => address) ownerToOrganisation;
  address[] allOrganisations;
  constructor(){

  }

  function createOrganisation(address _tokenAddress, string memory _name, string memory _symbol) external{
      Streamer streamer = new Streamer(_tokenAddress, _name, _symbol, msg.sender);
      ownerToOrganisation[msg.sender] = address(streamer);
      allOrganisations.push(address(streamer));
  }
}
