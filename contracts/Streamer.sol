// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/IEmployeeManagement.sol";
import "../library/Error.sol";
import "../library/Utils.sol";

/**
 * Notes
 * - Adds real employee lifecycle (invite → accept/reject → active/inactive)
 * - Streams salary pro‑rata per second into availableBalance
 * - Tracks totalMonthlySalary correctly
 * - Accrual happens lazily on actions or via public accrue functions
 * - Uses SafeERC20 and ReentrancyGuard for safety
 * - Emits events for off‑chain tracking
 */
contract Streamer is IEmployeeManagement, ReentrancyGuard {
    using SafeERC20 for IERC20;

    string public organisationName;
    string public organisationSymbol;

    IERC20 public salaryToken;
    address public owner;

    mapping(address => bool) public isAdmin;

    mapping(address => Employee) internal addressToEmployee;
    Employee[] internal employees;


    bool public allowWithdrawal = true;
    uint256 public totalMonthlySalary;

    struct Invite {
        bytes32 hash;
        uint256 salary;
        bool used;
    }
    mapping(address => Invite) public invites;

    mapping(address => uint256) public lastAccrued;

    uint256 private constant SECONDS_PER_MONTH = 30 days;



    modifier OnlyAdmin() {
        require(isAdmin[msg.sender], Error.ONLY_OWNER());
        _;
    }

    modifier OnlyOwner() {
        require(msg.sender == owner, Error.ONLY_OWNER());
        _;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────────────────────
    constructor(
        address _tokenAddress,
        string memory _organisationName,
        string memory _organisationSymbol,
        address _owner
    ) {
        require(_tokenAddress != address(0) && _owner != address(0), Error.INVALID_ADDRESS());
        salaryToken = IERC20(_tokenAddress);
        organisationName = _organisationName;
        organisationSymbol = _organisationSymbol;
        owner = _owner;
        isAdmin[_owner] = true;
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Treasury
    // ─────────────────────────────────────────────────────────────────────────────
    function depositToTreasury(uint256 _amount) external {
        require(_amount > Utils.ZERO, Error.ZERO_AMOUNT_INVALID_AMOUNT());
        salaryToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit TreasuryDeposited(msg.sender, _amount);
    }

    function viewTreasuryBalance() external view returns (uint256) {
        return salaryToken.balanceOf(address(this));
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Invites & Hiring
    // ─────────────────────────────────────────────────────────────────────────────
    function inviteEmployee(address _employee, uint256 _salary) external OnlyAdmin returns (bytes32) {
        require(_employee != address(0), Error.INVALID_ADDRESS());
        require(_salary > Utils.ZERO, Error.ZERO_AMOUNT_INVALID_AMOUNT());
        require(addressToEmployee[_employee].status != Status.ACTIVE, Error.EMPLOYEE_ALREADY_ACTIVE());

        // nonce includes current block + caller for uniqueness
        bytes32 inviteHash = keccak256(abi.encodePacked(address(this), _employee, _salary, msg.sender, block.timestamp));
        invites[_employee] = Invite({hash: inviteHash, salary: _salary, used: false});

        // mark status as INVITED for visibility
        addressToEmployee[_employee].status = Status.INVITED;

        emit EmployeeInvited(_employee, _salary, inviteHash);
        return inviteHash;
    }

    function employeeAcceptInvite(bytes32 _inviteHash) external {
        Invite storage inv = invites[msg.sender];
        require(!inv.used, Error.INVITE_USED());
        require(inv.hash != bytes32(0) && inv.hash == _inviteHash, Error.INVALID_INVITE_CODE());

        // Create / update employee record
        _accrue(msg.sender); // no‑op first time
        addressToEmployee[msg.sender].monthlySalary = inv.salary;
        addressToEmployee[msg.sender].status = Status.ACTIVE;
        addressToEmployee[msg.sender].id = employees.length;

        // Payroll totals and accrual start
        totalMonthlySalary += inv.salary;
        lastAccrued[msg.sender] = block.timestamp;

        // Best‑effort snapshot push (won't auto‑sync)
        employees.push(addressToEmployee[msg.sender]);

        inv.used = true;
        emit EmployeeAccepted(msg.sender, inv.salary);
    }

    function employeeRejectInvite(bytes32 _inviteHash) external {
        Invite storage inv = invites[msg.sender];
        require(!inv.used, Error.INVITE_USED());
        require(inv.hash != bytes32(0) && inv.hash == _inviteHash, Error.INVALID_INVITE_CODE());

        addressToEmployee[msg.sender].status = Status.REJECTED_INVITE;
        inv.used = true;

        emit EmployeeRejected(msg.sender);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Accrual (streaming per second)
    // ─────────────────────────────────────────────────────────────────────────────
    function _accrue(address _employeeAddress) internal {
        if (addressToEmployee[_employeeAddress].status != Status.ACTIVE) return;
        uint256 last = lastAccrued[_employeeAddress];
        if (last == Utils.ZERO) {
            lastAccrued[_employeeAddress] = block.timestamp;
            return;
        }
        uint256 deltaTime = block.timestamp - last;
        if (deltaTime == Utils.ZERO) return;

        uint256 _monthlySalary = addressToEmployee[_employeeAddress].monthlySalary;
        if (_monthlySalary == Utils.ZERO) {
            lastAccrued[_employeeAddress] = block.timestamp;
            return;
        }

        // accrue = monthlySalary * dt / 30 days
        uint256 earned = (_monthlySalary * deltaTime) / SECONDS_PER_MONTH;
        if (earned > Utils.ZERO) {
            addressToEmployee[_employeeAddress].availableBalance += earned;
            addressToEmployee[_employeeAddress].totalAccruedEarnings += earned;
        }
        lastAccrued[_employeeAddress] = block.timestamp;
    }

    function accrueMe() external {
        _accrue(msg.sender);
    }

    function accrueEmployee(address _employeeAddress) external OnlyAdmin {
        _accrue(_employeeAddress);
    }

    function accrueMany(address[] calldata _employeeAddresses) external OnlyAdmin {
        for (uint256 i = 0; i < _employeeAddresses.length; i++) {
            _accrue(_employeeAddresses[i]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Withdrawals
    // ─────────────────────────────────────────────────────────────────────────────
    function withdrawSalary(uint256 _amount) external nonReentrant {
        require(allowWithdrawal, Error.WITHDRAWAL_PAUSED());
        require(_amount > Utils.ZERO, Error.ZERO_AMOUNT_INVALID_AMOUNT());

        _accrue(msg.sender);
        require(_amount <= addressToEmployee[msg.sender].availableBalance, Error.INSUFFICIENT_BALANCE());

        addressToEmployee[msg.sender].availableBalance -= _amount;
        addressToEmployee[msg.sender].totalWithdrawn += _amount;

        salaryToken.safeTransfer(msg.sender, _amount);
        emit Withdrawal(msg.sender, _amount);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Admin controls
    // ─────────────────────────────────────────────────────────────────────────────
    function updateEmployeeStatus(address employeeAddress, Status _newStatus) external OnlyAdmin {
        Status oldStatus = addressToEmployee[employeeAddress].status;
        if (oldStatus == _newStatus) return;

        // Adjust payroll totals on active <-> non‑active transitions
        if (oldStatus == Status.ACTIVE && _newStatus != Status.ACTIVE) {
            _accrue(employeeAddress);
            totalMonthlySalary -= addressToEmployee[employeeAddress].monthlySalary;
        } else if (oldStatus != Status.ACTIVE && _newStatus == Status.ACTIVE) {
            lastAccrued[employeeAddress] = block.timestamp;
            totalMonthlySalary += addressToEmployee[employeeAddress].monthlySalary;
        }
        addressToEmployee[employeeAddress].status = _newStatus;
        emit EmployeeStatusUpdated(employeeAddress, oldStatus, _newStatus);
    }

    function updateMonthlySalary(address employeeAddress, uint256 newMonthlySalary) external OnlyAdmin {
        require(newMonthlySalary > Utils.ZERO, Error.ZERO_AMOUNT_INVALID_AMOUNT());
        _accrue(employeeAddress);

        uint256 oldSalary = addressToEmployee[employeeAddress].monthlySalary;
        if (addressToEmployee[employeeAddress].status == Status.ACTIVE) {
            if (newMonthlySalary >= oldSalary) {
                totalMonthlySalary += (newMonthlySalary - oldSalary);
            } else {
                totalMonthlySalary -= (oldSalary - newMonthlySalary);
            }
        }
        addressToEmployee[employeeAddress].monthlySalary = newMonthlySalary;
        emit SalaryUpdated(employeeAddress, oldSalary, newMonthlySalary);
    }

    function emergencyPause() external OnlyAdmin {
        allowWithdrawal = false;
        emit EmergencyPause(true);
    }

    function reverseEmergencyPause() external OnlyAdmin {
        allowWithdrawal = true;
        emit EmergencyPause(false);
    }

    function addAdmin(address newAdmin) external OnlyOwner {
        require(newAdmin != address(0), Error.INVALID_ADDRESS());
        isAdmin[newAdmin] = true;
        emit AdminAdded(newAdmin);
    }

    function removeAdmin(address adminToRemove) external OnlyOwner {
        isAdmin[adminToRemove] = false;
        emit AdminRemoved(adminToRemove);
    }

    // Owner can recover tokens (including salaryToken) in emergencies / shutdowns
    function emergencyRecoverToken(address token, address to, uint256 amount) external OnlyOwner {
        require(to != address(0), Error.INVALID_ADDRESS());
        IERC20(token).safeTransfer(to, amount);
        emit EmergencyTokenRecovered(token, to, amount);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Views (kept compatible with your originals)
    // ─────────────────────────────────────────────────────────────────────────────
    function getTotalMonthlyPayroll() external view OnlyAdmin returns (uint256) {
        return totalMonthlySalary;
    }

    function getAllEmployees() external view OnlyAdmin returns (Employee[] memory) {
        return employees;
    }

    function getTotalEarnings() external view returns (uint256) {
        return addressToEmployee[msg.sender].totalAccruedEarnings;
    }

    function getTotalWithdrawn() external view returns (uint256) {
        return addressToEmployee[msg.sender].totalWithdrawn;
    }

    function getMonthlySalary() external view returns (uint256) {
        return addressToEmployee[msg.sender].monthlySalary;
    }

    function getEmployeeStatus() external view returns (Status) {
        return addressToEmployee[msg.sender].status;
    }

    function getEmployeeInfo() external view returns (Employee memory) {
        return addressToEmployee[msg.sender];
    }

    function adminGetEmployeeInfoByAddress(address _employeeAddr) external view returns (Employee memory) {
        return addressToEmployee[_employeeAddr];
    }

    function adminGetEmployeeInfoById(uint256 _id) external view returns (Employee memory) {
        require(_id < employees.length, Error.INVALID_ID());
        return employees[_id];
    }

    // Helper to reproduce the invite hash off‑chain for verification
    function hashInvite(address _employee, uint256 _salary, address _inviter, uint256 _timestampSeed) external view returns (bytes32) {
        // Mirrors inviteEmployee encoder. Not strictly necessary but helps frontend testing.
        return keccak256(abi.encodePacked(address(this), _employee, _salary, _inviter, _timestampSeed));
    }

    // Lock employee salary that has not been  withdrawn at the end of the month so employer will not take it out;
    // if employee salary is not withdrawn within 3 months, employer can take it out.
    // if employer what to penalize employee for misconduct, or for any other reason, employer can take out the salary
}
