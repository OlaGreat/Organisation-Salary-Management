import { expect } from "chai";
import { ethers } from "hardhat";
import { Streamer, Factory, ERC20Mock } from "../typechain-types";

describe("Factory + Streamer Payroll System", function () {
  let factory: Factory;
  let salaryToken: ERC20Mock;
  let streamer: Streamer;
  let owner: any, admin: any, employee: any, outsider: any;

  beforeEach(async () => {
    [owner, admin, employee, outsider] = await ethers.getSigners();

    // Deploy mock ERC20 as salary token
    const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    salaryToken = await ERC20Mock.deploy("Mock USD", "mUSD", owner.address, ethers.parseEther("1000000"));
    await salaryToken.waitForDeployment();

    // Deploy Factory
    const Factory = await ethers.getContractFactory("Factory");
    factory = await Factory.deploy();
    await factory.waitForDeployment();

    // Create one organisation
    await factory.connect(owner).createOrganisation(
      await salaryToken.getAddress(),
      "MyOrg",
      "ORG"
    );

    const orgs = await factory.getOwnedOrganisations();
    streamer = await ethers.getContractAt("Streamer", orgs[0]);
  });

  it("should deploy with correct owner and token", async () => {
    expect(await streamer.owner()).to.equal(owner.address);
    expect(await streamer.salaryToken()).to.equal(await salaryToken.getAddress());
  });

  it("owner can deposit to treasury", async () => {
    const amount = ethers.parseEther("1000");
    await salaryToken.connect(owner).approve(await streamer.getAddress(), amount);
    await streamer.connect(owner).depositToTreasury(amount);

    expect(await streamer.viewTreasuryBalance()).to.equal(amount);
  });

  it("admin can invite and employee can accept", async () => {
    const salary = ethers.parseEther("1000");

     await streamer
      .connect(owner)
      .inviteEmployee(employee.address, salary, "John", "Doe", "Engineer", "Tech", Math.floor(Date.now()/1000));

    const invite = await streamer.invites(employee.getAddress());
    
    await streamer.connect(employee).employeeAcceptInvite(invite.hash);

    const empInfo = await streamer.adminGetEmployeeInfoByAddress(employee.address);
    expect(empInfo.status).to.equal(1); // ACTIVE
    expect(empInfo.monthlySalary).to.equal(salary);
  });

  it("employee accrues earnings over time", async () => {
    const salary = ethers.parseEther("3000");
    await streamer
      .connect(owner)
      .inviteEmployee(employee.address, salary, "John", "Doe", "Engineer", "Tech", Math.floor(Date.now()/1000));

    const invite = await streamer.invites(employee.getAddress());
    await streamer.connect(employee).employeeAcceptInvite(invite.hash);

    // Fast forward time ~15 days
    await ethers.provider.send("evm_increaseTime", [15 * 24 * 3600]);
    await ethers.provider.send("evm_mine", []);

    const earnings = await streamer.getAvailableEarnings(employee.address);
    expect(earnings).to.be.gt(0);
  });

  it("employee can withdraw salary", async () => {
    const salary = ethers.parseEther("3000");
    const amount = ethers.parseEther("1000");

    // deposit treasury
    await salaryToken.connect(owner).approve(await streamer.getAddress(), ethers.parseEther("10000"));
    await streamer.connect(owner).depositToTreasury(ethers.parseEther("10000"));

    await streamer
      .connect(owner)
      .inviteEmployee(employee.address, salary, "John", "Doe", "Engineer", "Tech", Math.floor(Date.now()/1000));

    const invite = await streamer.invites(employee.getAddress());
    await streamer.connect(employee).employeeAcceptInvite(invite.hash);

    // Increase time so they accrue earnings
    await ethers.provider.send("evm_increaseTime", [31 * 24 * 3600]); // 1 month
    await ethers.provider.send("evm_mine", []);

    const available = await streamer.getAvailableEarnings(employee.address);
    
  
    expect(available).to.be.gte(salary);

    await streamer.connect(employee).withdrawSalary(amount);

    const bal = await salaryToken.balanceOf(employee.address);
    expect(bal).to.closeTo(amount, ethers.parseEther('1'));
  });

  it("factory should register employee with organisation", async () => {
    const salary = ethers.parseEther("2000");
    await streamer
      .connect(owner)
      .inviteEmployee(employee.address, salary, "John", "Doe", "Engineer", "Tech", Math.floor(Date.now()/1000));

    const invite = await streamer.invites(employee.getAddress());
    await streamer.connect(employee).employeeAcceptInvite(invite.hash);
    const employeeOrgs = await factory.connect(employee).getEmployeeOrganisations();
    expect(employeeOrgs.length).to.equal(1);
    expect(employeeOrgs[0]).to.equal(await streamer.getAddress());
  });

  it("owner can add/remove admins", async () => {
    await streamer.connect(owner).addAdmin(admin.address);
    expect(await streamer.isAdmin(admin.address)).to.equal(true);

    await streamer.connect(owner).removeAdmin(admin.address);
    expect(await streamer.isAdmin(admin.address)).to.equal(false);
  });

  it("admin can punish employee", async () => {
    const salary = ethers.parseEther("2000");
    await salaryToken.connect(owner).approve(await streamer.getAddress(), ethers.parseEther("10000"));
    await streamer.connect(owner).depositToTreasury(ethers.parseEther("10000"));

    const inviteHash = await streamer
      .connect(owner)
      .inviteEmployee(employee.address, salary, "Sam", "Lee", "Ops", "Tech", Math.floor(Date.now()/1000));
    const invite = await streamer.invites(employee.getAddress());
      await streamer.connect(employee).employeeAcceptInvite(invite.hash);

    // Move time so earnings accrue
    await ethers.provider.send("evm_increaseTime", [30 * 24 * 3600]);
    await ethers.provider.send("evm_mine", []);

    const before = await streamer.getAvailableEarnings(employee.address);
    await streamer.connect(owner).punishEmployee(employee.address, ethers.parseEther("500"));

    const after = await streamer.getAvailableEarnings(employee.address);
    expect(after).to.be.closeTo(before - ethers.parseEther("500"), ethers.parseEther("1"));
  });
});
