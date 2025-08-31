// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

interface IEmployeeManagement {
    struct Employee{
        uint256  id;
        string firstName;
        string lastName;
        string position;
        string department;
        uint256 date_hired;
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
    event EmployeePunished(address indexed employee, uint256 amount);

    function depositToTreasury(uint256 _amount) external;
    function viewTreasuryBalance() external view returns (uint256);

    function inviteEmployee(address _employeeAddress, uint256 _salary) external returns (bytes32);
    function employeeAcceptInvite(bytes32 _inviteHash) external;
    function employeeRejectInvite(bytes32 _inviteHash) external;

    function accrueMe() external;
    function accrueEmployee(address _employeeAddress) external;
    function accrueMany(address[] calldata _employeeAddresses) external;

    function withdrawSalary(uint256 _amount) external;

    function updateEmployeeStatus(address employeeAddress, Status _status) external;
    function updateMonthlySalary(address employeeAddress, uint256 newMonthlySalary) external;

    function emergencyPause() external;
    function reverseEmergencyPause() external;

    function addAdmin(address newAdmin) external;
    function removeAdmin(address adminToRemove) external;
    function emergencyRecoverToken(address token, address to, uint256 amount) external;

    function getTotalMonthlyPayroll() external view returns (uint256);
    function getAllEmployees() external view returns (Employee[] memory);
    function getTotalEarnings() external view returns (uint256);
    function getTotalWithdrawn() external view returns (uint256);
    function getMonthlySalary() external view returns (uint256);
    function getEmployeeStatus() external view returns (Status);



}
