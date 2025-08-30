// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IEmployeeManagement {
    struct Employee{
        uint256  id;
        uint256 monthlySalary;
        Status  status;
        uint256 totalWithdrawn;
        uint256 availableBalance;
        uint256 totalAccruedEarnings;
    }

    enum Status {
        INVITED,
        ACTIVE,
        INACTIVE,
        TERMINATED,
        REJECTED_INVITE
    }


    event TreasuryDeposited(address indexed from, uint256 amount);
    event EmployeeInvited(address indexed employee, uint256 salary, bytes32 inviteHash);
    event EmployeeAccepted(address indexed employee, uint256 salary);
    event EmployeeRejected(address indexed employee);
    event EmployeeStatusUpdated(address indexed employee, Status oldStatus, Status newStatus);
    event SalaryUpdated(address indexed employee, uint256 oldSalary, uint256 newSalary);
    event Withdrawal(address indexed employee, uint256 amount);
    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
    event EmergencyPause(bool paused);
    event EmergencyTokenRecovered(address indexed token, address indexed to, uint256 amount);


}
