const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("VEMPPool", function () {
  let MasterChefVEMP, masterChef, owner, addr1, addr2;
  let VEMPPerBlock = ethers.utils.parseEther("10"); // 10 VEMP per block
  let startBlock = 0; // Mining starts at block 100

  beforeEach(async function () {
    // Get contract factories
    MasterChefVEMP = await ethers.getContractFactory("VEMPPool");

    // Get signers
    [owner, addr1, addr2] = await ethers.getSigners();

    // Deploy proxy contract using OpenZeppelin Upgrades plugin
    masterChef = await upgrades.deployProxy(
      MasterChefVEMP,
      [owner.address, VEMPPerBlock, startBlock],
      { initializer: "initialize" }
    );

    await masterChef.deployed();
  });

  describe("Deployment", function () {
    it("Should deploy with the correct owner", async function () {
      expect(await masterChef.owner()).to.equal(owner.address);
    });

    it("Should set VEMPPerBlock correctly", async function () {
      const rewardPerBlock = await masterChef.VEMPPerBlock();
      expect(rewardPerBlock).to.equal(VEMPPerBlock);
    });

    it("Should set the correct start block", async function () {
      expect(await masterChef.startBlock()).to.equal(startBlock);
    });
  });

  describe("Deposits", function () {
    it("Should allow users to deposit and update user balances", async function () {
      const depositAmount = ethers.utils.parseEther("1"); // 1 ETH

      await masterChef.connect(addr1).deposit(depositAmount, { value: depositAmount });
      const userInfo = await masterChef.userInfo(addr1.address);

      expect(userInfo.amount).to.equal(depositAmount.toString());
      expect(await masterChef.totalVEMPStaked()).to.equal(depositAmount.toString());
    });

    it("Should emit a Deposit event on successful deposit", async function () {
      const depositAmount = ethers.utils.parseEther("1"); // 1 ETH

      await expect(masterChef.connect(addr1).deposit(depositAmount, { value: depositAmount }))
        .to.emit(masterChef, "Deposit")
        .withArgs(addr1.address, depositAmount);
    });

    it("Should not allow blacklisted users to deposit", async function () {
      const depositAmount = ethers.utils.parseEther("1"); // 1 ETH
      await masterChef.blackListAddress(addr1.address, true);

      await expect(
        masterChef.connect(addr1).deposit(depositAmount, { value: depositAmount })
      ).to.be.revertedWith("Not allowed");
    });
  });

  describe("Rewards", function () {
    it("Should calculate pending rewards correctly", async function () {
      const depositAmount = ethers.utils.parseEther("1"); // 1 ETH

      // Deposit
      await masterChef.connect(addr1).deposit(depositAmount, { value: depositAmount });

      // Fast forward to the next block
      await ethers.provider.send("evm_mine");

      // Check pending rewards
      const pending = await masterChef.pendingVEMP(addr1.address);
      const expectedReward = ethers.utils.parseEther("10"); // 1 block * 10 VEMP per block

      expect(pending).to.equal(expectedReward);
    });

    it("Should update the reward per block", async function () {
      const newVEMPPerBlock = ethers.utils.parseEther("20"); // 20 VEMP per block

      await masterChef.updateRewardPerBlock(newVEMPPerBlock);

      expect(await masterChef.VEMPPerBlock()).to.equal(newVEMPPerBlock);
    });

    it("Should not allow rewards after the reward end block", async function () {
      const depositAmount = ethers.utils.parseEther("1"); // 1 ETH
      await masterChef.connect(addr1).deposit(depositAmount, { value: depositAmount });

      // Fast forward to the reward end block
      for (let i = 0; i < 11; i++) {
        await ethers.provider.send("evm_mine");
      }

      // No rewards after reward end block
      const pending = await masterChef.pendingVEMP(addr1.address);
      expect(pending).to.equal("110000000000000000000");
    });

    it("Should not distribute reward after setting rewardPerBlock to 0", async function () {
      // Deposit some ETH to earn rewards
      await masterChef.connect(addr1).deposit(ethers.utils.parseEther("10"), {
        value: ethers.utils.parseEther("10"),
      });

      // Advance by 10 blocks to accumulate some rewards
      for (let i = 0; i < 10; i++) {
        await network.provider.send("evm_mine");
      }

      // Check pending rewards before setting reward per block to 0
      let pendingRewardBefore = await masterChef.pendingVEMP(addr1.address);
      expect(pendingRewardBefore).to.be.gt(0); // Should have some pending rewards

      // Set reward per block to 0
      await masterChef.updateRewardPerBlock(0);

      // Advance by 10 more blocks
      for (let i = 0; i < 10; i++) {
        await network.provider.send("evm_mine");
      }

      // Check pending rewards after setting reward per block to 0
      let pendingRewardAfter = await masterChef.pendingVEMP(addr1.address);

      // The pending reward after should be the same as before, as no more rewards should accumulate
      expect(pendingRewardAfter).to.equal("110000000000000000000");

      // Withdraw LP tokens and claim rewards
      await masterChef.connect(addr1).withdraw(ethers.utils.parseEther("10"));
    });
  });

  describe("Withdrawals", function () {
    it("Should allow users to withdraw their deposits", async function () {
      const depositAmount = ethers.utils.parseEther("1"); // 1 ETH

      await masterChef.connect(addr1).deposit(depositAmount, { value: depositAmount });
      await masterChef.connect(addr1).withdraw(depositAmount);

      const userInfo = await masterChef.userInfo(addr1.address);
      expect(userInfo.amount).to.equal(0);
      expect(await masterChef.totalVEMPStaked()).to.equal(0);
    });

    it("Should emit a Withdraw event on successful withdrawal", async function () {
      const depositAmount = ethers.utils.parseEther("1"); // 1 ETH

      await masterChef.connect(addr1).deposit(depositAmount, { value: depositAmount });
      await expect(masterChef.connect(addr1).withdraw(depositAmount))
        .to.emit(masterChef, "Withdraw")
        .withArgs(addr1.address, depositAmount);
    });

    it("Should not allow blacklisted users to withdraw", async function () {
      const depositAmount = ethers.utils.parseEther("1"); // 1 ETH

      await masterChef.connect(addr1).deposit(depositAmount, { value: depositAmount });
      await masterChef.blackListAddress(addr1.address, true);

      await expect(
        masterChef.connect(addr1).withdraw(depositAmount)
      ).to.be.revertedWith("Not allowed");
    });
  });

  describe("Admin Functions", function () {
    it("Should update reward per block", async function () {
      const oldRewardPerBlock = await masterChef.VEMPPerBlock();
      const newRewardPerBlock = ethers.utils.parseEther("2");

      await masterChef.updateRewardPerBlock(newRewardPerBlock);

      expect(await masterChef.VEMPPerBlock()).to.equal(newRewardPerBlock);
      expect(await masterChef.VEMPPerBlock()).to.not.equal(oldRewardPerBlock);
    });
  });
});