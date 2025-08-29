// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "../interfaces/IEmployeeManagement.sol";

contract Streamer is IEmployeeManagement{
   string organisationName;
   string  strorganisationSymbol;
   address owner;
   mapping(address => bool) isAdmin;
   mapping(address => Employee) addressToEmployee;
   Employee[] employees;
   uint256 employeeId = employees.length;
   bool allowWithdrawal;
   uint256 totalMonthlySalary;
   mapping (address => bytes) addressToInviteHash;

    constructor(){

    }
}
