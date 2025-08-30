// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/IEmployeeManagement.sol"; // assumes Employee struct + Status enum exposed

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

    // ─────────────────────────────────────────────────────────────────────────────
    // Storage
    // ─────────────────────────────────────────────────────────────────────────────
    string public organisationName;
    string public organisationSymbol;

    IERC20 public salaryToken;
    address public owner;

    mapping(address => bool) public isAdmin;

    // Core employee storage (struct defined in IEmployeeManagement)
    mapping(address => Employee) internal addressToEmployee;
    Employee[] internal employees; // snapshot list (best effort)

    // Book‑keeping
    bool public allowWithdrawal = true;
    uint256 public totalMonthlySalary; // sum of all active employees' monthlySalary

    // Invite handling with nonce to prevent preimage/replay collisions
    struct Invite {
        bytes32 hash;
        uint256 salary;
        bool used; // set true on accept/reject
    }
    mapping(address => Invite) public invites;

    // Streaming accrual state (kept outside Employee struct for interface safety)
    mapping(address => uint256) public lastAccrued; // timestamp of last accrual

    // Constants
    uint256 private constant SECONDS_PER_MONTH = 30 days; // simple 30‑day month


    // ─────────────────────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────────────────────
    modifier OnlyAdmin() {
        require(isAdmin[msg.sender], "Only Admin");
        _;
    }

    modifier OnlyOwner() {
        require(msg.sender == owner, "Only Owner");
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
        require(_tokenAddress != address(0) && _owner != address(0), "Zero addr");
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
        require(_amount > 0, "Zero deposit");
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
        require(_employee != address(0), "Zero employee");
        require(_salary > 0, "Zero salary");
        require(addressToEmployee[_employee].status != Status.ACTIVE, "Already active");

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
        require(!inv.used, "Invite used");
        require(inv.hash != bytes32(0) && inv.hash == _inviteHash, "Bad invite");

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
        require(!inv.used, "Invite used");
        require(inv.hash != bytes32(0) && inv.hash == _inviteHash, "Bad invite");

        addressToEmployee[msg.sender].status = Status.REJECTED_INVITE;
        inv.used = true;

        emit EmployeeRejected(msg.sender);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Accrual (streaming per second)
    // ─────────────────────────────────────────────────────────────────────────────
    function _accrue(address _emp) internal {
        if (addressToEmployee[_emp].status != Status.ACTIVE) return;
        uint256 last = lastAccrued[_emp];
        if (last == 0) {
            lastAccrued[_emp] = block.timestamp;
            return;
        }
        uint256 dt = block.timestamp - last;
        if (dt == 0) return;

        uint256 msal = addressToEmployee[_emp].monthlySalary;
        if (msal == 0) {
            lastAccrued[_emp] = block.timestamp;
            return;
        }

        // accrue = monthlySalary * dt / 30 days
        uint256 earned = (msal * dt) / SECONDS_PER_MONTH;
        if (earned > 0) {
            addressToEmployee[_emp].availableBalance += earned;
            addressToEmployee[_emp].totalAccruedEarnings += earned;
        }
        lastAccrued[_emp] = block.timestamp;
    }

    function accrueMe() external {
        _accrue(msg.sender);
    }

    function accrueEmployee(address _emp) external OnlyAdmin {
        _accrue(_emp);
    }

    function accrueMany(address[] calldata _emps) external OnlyAdmin {
        for (uint256 i = 0; i < _emps.length; i++) {
            _accrue(_emps[i]);
        }
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Withdrawals
    // ─────────────────────────────────────────────────────────────────────────────
    function withdrawSalary(uint256 _amount) external nonReentrant {
        require(allowWithdrawal, "Withdrawals paused");
        require(_amount > 0, "Zero amount");

        _accrue(msg.sender);
        require(_amount <= addressToEmployee[msg.sender].availableBalance, "Insufficient avail");

        addressToEmployee[msg.sender].availableBalance -= _amount;
        addressToEmployee[msg.sender].totalWithdrawn += _amount;

        salaryToken.safeTransfer(msg.sender, _amount);
        emit Withdrawal(msg.sender, _amount);
    }

    // ─────────────────────────────────────────────────────────────────────────────
    // Admin controls
    // ─────────────────────────────────────────────────────────────────────────────
    function updateEmployeeStatus(address employeeAddress, Status _status) external OnlyAdmin {
        Status old = addressToEmployee[employeeAddress].status;
        if (old == _status) return;

        // Adjust payroll totals on active <-> non‑active transitions
        if (old == Status.ACTIVE && _status != Status.ACTIVE) {
            _accrue(employeeAddress);
            totalMonthlySalary -= addressToEmployee[employeeAddress].monthlySalary;
        } else if (old != Status.ACTIVE && _status == Status.ACTIVE) {
            lastAccrued[employeeAddress] = block.timestamp;
            totalMonthlySalary += addressToEmployee[employeeAddress].monthlySalary;
        }
        addressToEmployee[employeeAddress].status = _status;
        emit EmployeeStatusUpdated(employeeAddress, old, _status);
    }

    function updateMonthlySalary(address employeeAddress, uint256 newMonthlySalary) external OnlyAdmin {
        require(newMonthlySalary > 0, "Zero salary");
        _accrue(employeeAddress);

        uint256 old = addressToEmployee[employeeAddress].monthlySalary;
        if (addressToEmployee[employeeAddress].status == Status.ACTIVE) {
            // keep payroll total in sync
            if (newMonthlySalary >= old) {
                totalMonthlySalary += (newMonthlySalary - old);
            } else {
                totalMonthlySalary -= (old - newMonthlySalary);
            }
        }
        addressToEmployee[employeeAddress].monthlySalary = newMonthlySalary;
        emit SalaryUpdated(employeeAddress, old, newMonthlySalary);
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
        require(newAdmin != address(0), "Zero admin");
        isAdmin[newAdmin] = true;
        emit AdminAdded(newAdmin);
    }

    function removeAdmin(address adminToRemove) external OnlyOwner {
        isAdmin[adminToRemove] = false;
        emit AdminRemoved(adminToRemove);
    }

    function punishEmployee(address employeeAddress, uint256 penaltyAmount) external OnlyAdmin {
        require(penaltyAmount > 0, "Zero penalty");
        require(addressToEmployee[employeeAddress].status == Status.ACTIVE, "Not active");

        _accrue(employeeAddress); // bring balances current

        Employee storage emp = addressToEmployee[employeeAddress];
        require(penaltyAmount <= emp.availableBalance, "Penalty exceeds balance");

        emp.availableBalance -= penaltyAmount;
        emp.totalAccruedEarnings -= penaltyAmount; // reflect reduction in total earnings

        emit EmployeePunished(employeeAddress, penaltyAmount);
    }


    // Owner can recover tokens (including salaryToken) in emergencies / shutdowns
    function emergencyRecoverToken(address token, address to, uint256 amount) external OnlyOwner {
        require(to != address(0), "Zero to");
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

    function getAvailableEarnings(address employeeAddress) public view returns (uint256) {
    Employee memory emp = addressToEmployee[employeeAddress];
    if (emp.status != Status.ACTIVE) return emp.availableBalance;

    // How much time has passed since lastAccrued
    uint256 elapsed = block.timestamp - lastAccrued[employeeAddress];

    // Accrued per second
    uint256 perSecond = emp.monthlySalary / (30 days);

    uint256 pending = elapsed * perSecond;

    return emp.availableBalance + pending;
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
        require(_id < employees.length, "Invalid Id");
        return employees[_id];
    }

    // Helper to reproduce the invite hash off‑chain for verification
    function hashInvite(address _employee, uint256 _salary, address _inviter, uint256 _timestampSeed) external view returns (bytes32) {
        // Mirrors inviteEmployee encoder. Not strictly necessary but helps frontend testing.
        return keccak256(abi.encodePacked(address(this), _employee, _salary, _inviter, _timestampSeed));
    }
}
