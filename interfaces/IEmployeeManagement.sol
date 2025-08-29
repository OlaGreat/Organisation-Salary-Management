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
        PENDING,
        ACTIVE,
        INACTIVE,
        TERMINATED,
        REJECTED
    }

}
