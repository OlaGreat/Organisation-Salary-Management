// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../interfaces/IEmployeeManagement.sol";
import "../library/Error.sol";


contract Streamer is IEmployeeManagement{
   string organisationName;
   string  organisationSymbol;
   address owner;
   mapping(address => bool) isAdmin;
   mapping(address => Employee) addressToEmployee;
   Employee[] employees;
   uint256 employeeId = employees.length;
   bool allowWithdrawal;
   uint256 totalMonthlySalary;
   mapping (address => bytes) addressToInviteHash;

    constructor(string memory _organisationName, string memory _organisationSymbol, address _owner){
       require(address != address (0), INVALID_ADDRESS());
       organisationName = _organisationName;
       organisationSymbol = _organisationSymbol;
       owner = _owner;
    }
}
