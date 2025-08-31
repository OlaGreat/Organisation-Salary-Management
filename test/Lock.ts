import { expect } from "chai";
import { ethers } from "hardhat";
import { Contract, Signer } from "ethers";

describe("Factory + Streamer", function () {
  let factory: Contract;
  let salaryToken: Contract;
  let streamer: Contract;

  let owner: Signer;
  let admin: Signer;
  let employee1: Signer;
  let employee2: Signer;
  let outsider: Signer;

  beforeEach(async () => {
    [owner, admin, employee1, employee2, outsider] = await ethers.getSigners();

    // Deploy a mock ERC20 (salary token)
    const ERC20 = await ethers.getContractFactory("ERC20Mock"); // assume OpenZeppelin ERC20Mock in test env
    salaryToken = await ERC20.deploy(
      "MockToken",
      "MTK",
      await owner.getAddress(),
      ethers.parseEther("1000000")
    );

    // Deploy Factory
    const Factory = await ethers.getContractFactory("Factory");
    factory = await Factory.deploy();

    // Create an Organisation
    await factory
      .connect(owner)
      .createOrganisation(salaryToken.target, "OrgName", "ORG");

    const orgs = await factory.getOwnedOrganisations();
    expect(orgs.length).to.equal(1);

    streamer = await ethers.getContractAt("Streamer", orgs[0]);
  });

  describe("Organisation setup", () => {
    it("should assign owner as admin", async () => {
      expect(await streamer.isAdmin(await owner.getAddress())).to.be.true;
    });

    it("treasury deposit works", async () => {
      await salaryToken
        .connect(owner)
        .approve(streamer.target, ethers.parseEther("1000"));
      await expect(
        streamer.connect(owner).depositToTreasury(ethers.parseEther("1000"))
      ).to.emit(streamer, "TreasuryDeposited");
      expect(await streamer.viewTreasuryBalance()).to.equal(
        ethers.parseEther("1000")
      );
    });
  });

  describe("Invites & Hiring", () => {
    let inviteHash: string;

    beforeEach(async () => {
      inviteHash = await streamer
        .connect(owner)
        .inviteEmployee.staticCall(
          await employee1.getAddress(),
          ethers.parseEther("3000")
        );
      await streamer
        .connect(owner)
        .inviteEmployee(
          await employee1.getAddress(),
          ethers.parseEther("3000")
        );
    });

    it("owner can invite employee", async () => {
      const inv = await streamer.invites(await employee1.getAddress());
      expect(inv.salary).to.equal(ethers.parseEther("3000"));
    });

    it("employee accepts invite and becomes ACTIVE", async () => {
      const inv = await streamer.invites(await employee1.getAddress());
      await expect(
        streamer.connect(employee1).employeeAcceptInvite(inv.hash)
      ).to.emit(streamer, "EmployeeAccepted");
      const status = await streamer.connect(employee1).getEmployeeStatus();
      expect(status).to.equal(1); // Status.ACTIVE enum index
    });

    it("employee rejects invite", async () => {
      const inv = await streamer.invites(await employee1.getAddress());
      await expect(
        streamer.connect(employee1).employeeRejectInvite(inv.hash)
      ).to.emit(streamer, "EmployeeRejected");
      const status = await streamer.connect(employee1).getEmployeeStatus();
      expect(status).to.equal(4); // Status.REJECTED_INVITE
    });
  });

  describe("Accrual & Withdrawals", () => {
    beforeEach(async () => {
      
      await streamer
        .connect(owner)
        .inviteEmployee(
          await employee1.getAddress(),
          ethers.parseEther("3000")
        );
        const inv =await streamer.invites(await employee1.getAddress())
      await streamer.connect(employee1).employeeAcceptInvite(inv.hash);


      // Fund treasury
      await salaryToken
        .connect(owner)
        .approve(streamer.target, ethers.parseEther("10000"));
      await streamer
        .connect(owner)
        .depositToTreasury(ethers.parseEther("10000"));

        
    });

    it("accrues salary over time", async () => {
       let earnings = await streamer.getAvailableEarnings(
        await employee1.getAddress()
      );
      console.log("first day",ethers.formatEther(await streamer.getAvailableEarnings(await employee1.getAddress())));
      expect(earnings).to.be.closeTo(
        ethers.parseEther("0"),
        ethers.parseEther("1")
      );
      await ethers.provider.send("evm_increaseTime", [10 * 24 * 60 * 60]);
      await ethers.provider.send("evm_mine", []);

      earnings = await streamer.getAvailableEarnings(
        await employee1.getAddress()
      );
      expect(earnings).to.be.closeTo(
        ethers.parseEther("1000"),
        ethers.parseEther("1")
      );
      console.log("first 10 days",ethers.formatEther(await streamer.getAvailableEarnings(await employee1.getAddress())));
      await ethers.provider.send("evm_increaseTime", [10 * 24 * 60 * 60]);
      await ethers.provider.send("evm_mine", []);
      earnings = await streamer.getAvailableEarnings(
        await employee1.getAddress()
      );
      expect(earnings).to.be.closeTo(
        ethers.parseEther("2000"),
        ethers.parseEther("1")
      );
      console.log("next 10 days",ethers.formatEther(await streamer.getAvailableEarnings(await employee1.getAddress())));

      await ethers.provider.send("evm_increaseTime", [10 * 24 * 60 * 60]);
      await ethers.provider.send("evm_mine", []);
      earnings = await streamer.getAvailableEarnings(
        await employee1.getAddress()
      );
      expect(earnings).to.be.closeTo(
        ethers.parseEther("3000"),
        ethers.parseEther("1")
      );
    });

    it("employee withdraws accrued salary", async () => {
      await ethers.provider.send("evm_increaseTime", [15 * 24 * 60 * 60]);
      await ethers.provider.send("evm_mine", []);

      const available = await streamer.getAvailableEarnings(
        await employee1.getAddress()
      );
      await expect(
        streamer.connect(employee1).withdrawSalary(available)
      ).to.emit(streamer, "Withdrawal");

      expect(
        await salaryToken.balanceOf(await employee1.getAddress())
      ).to.equal(available);
    });

    it("cannot withdraw if paused", async () => {
      await streamer.connect(owner).emergencyPause();
      await expect(streamer.connect(employee1).withdrawSalary(1)).to.be
        .revertedWithCustomError;
    });
  });

  describe("Admin controls", () => {
    beforeEach(async () => {
      await streamer
        .connect(owner)
        .inviteEmployee(
          await employee1.getAddress(),
          ethers.parseEther("3000")
        );
        const inv =await streamer.invites(await employee1.getAddress())
      await streamer.connect(employee1).employeeAcceptInvite(inv.hash);
    });

    it("update salary adjusts payroll", async () => {
      await streamer
        .connect(owner)
        .updateMonthlySalary(
          await employee1.getAddress(),
          ethers.parseEther("4000")
        );
      const emp = await streamer.adminGetEmployeeInfoByAddress(
        await employee1.getAddress()
      );
      expect(emp.monthlySalary).to.equal(ethers.parseEther("4000"));
    });

    it("admin can punish employee", async () => {
      await ethers.provider.send("evm_increaseTime", [10 * 24 * 60 * 60]);
      await ethers.provider.send("evm_mine", []);

      const balBefore = await streamer.getAvailableEarnings(
        await employee1.getAddress()
      );
      await streamer
        .connect(owner)
        .punishEmployee(await employee1.getAddress(), balBefore / 2n);

      const balAfter = await streamer.getAvailableEarnings(
        await employee1.getAddress()
      );

      expect(balAfter).to.be.closeTo(balBefore / 2n, ethers.parseEther("2"));
    });

    it("owner can add/remove admins", async () => {
      await streamer.connect(owner).addAdmin(await admin.getAddress());
      expect(await streamer.isAdmin(await admin.getAddress())).to.be.true;

      await streamer.connect(owner).removeAdmin(await admin.getAddress());
      expect(await streamer.isAdmin(await admin.getAddress())).to.be.false;
    });
  });

  describe("Security checks", () => {
    it("non-owner cannot add admin", async () => {
      await expect(
        streamer.connect(employee1).addAdmin(await admin.getAddress())
      ).to.be.revertedWithCustomError;
    });

    it("cannot invite with zero salary", async () => {
      await expect(
        streamer.connect(owner).inviteEmployee(await employee1.getAddress(), 0)
      ).to.be.revertedWithCustomError;
    });

    it("cannot deposit zero", async () => {
      await expect(streamer.connect(owner).depositToTreasury(0)).to.be
        .revertedWithCustomError;
    });
  });
});
