const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("VEMPVault Contract", function () {
    let VEMPVault, vempVault;
    let owner, addr1, addr2, addr3;
    const VEMPPerBlock = ethers.utils.parseEther("1");
    const startBlock = 100;

    beforeEach(async function () {
        [owner, addr1, addr2, addr3] = await ethers.getSigners();
        VEMPVault = await ethers.getContractFactory("VEMPVault");
        vempVault = await upgrades.deployProxy(VEMPVault, [owner.address, addr1.address, VEMPPerBlock, startBlock], { initializer: "initialize" });
    });

    describe("Initialization", function () {
        it("Should initialize correctly", async function () {
            expect(await vempVault.receiver()).to.equal(addr1.address);
            expect(await vempVault.VEMPPerBlock()).to.equal(VEMPPerBlock);
            expect(await vempVault.startBlock()).to.equal(startBlock);
        });

        it("Should initialize pool info correctly", async function () {
            const poolInfo = await vempVault.poolInfo();
            expect(poolInfo.allocPoint).to.equal(100);
            expect(poolInfo.accVEMPPerShare).to.equal(0);
        });

        it("Should initialize the receiver with default LP tokens", async function () {
            const userInfo = await vempVault.userInfo(addr1.address);
            expect(userInfo.amount).to.equal(ethers.utils.parseEther("1"));
        });
    });

    describe("Whitelist Management", function () {
        it("Should allow owner to update whitelist", async function () {
            await vempVault.whitelistAddress(addr2.address, true);
            expect(await vempVault.isWhitelisted(addr2.address)).to.be.true;
        });

        it("Should emit an event on whitelist update", async function () {
            await expect(vempVault.whitelistAddress(addr2.address, true))
                .to.emit(vempVault, "WhitelistUpdated")
                .withArgs(addr2.address, true);
        });

        it("Should reject non-owner from updating whitelist", async function () {
            await expect(vempVault.connect(addr2).whitelistAddress(addr3.address, true)).to.be.revertedWith("OwnableUnauthorizedAccount");
        });
    });

    describe("Reward Calculation", function () {
        it("Should calculate pending rewards correctly", async function () {
            const multiplier = await vempVault.getMultiplier(100, 200);
            expect(multiplier).to.equal(100);
        });
    });

    describe("Reward Claiming", function () {
        beforeEach(async function () {
            await vempVault.whitelistAddress(addr1.address, true);
        });

        it("Should allow whitelisted users to claim rewards", async function () {
            await ethers.provider.send("evm_mine", []); // Mine a block
            await expect(vempVault.connect(addr1).claimPendingReward())
                .to.emit(vempVault, "Claim")
                .withArgs(addr1.address, addr1.address, ethers.utils.parseEther("3"));
        });

        it("Should revert for non-whitelisted users", async function () {
            await expect(vempVault.connect(addr2).claimPendingReward()).to.be.revertedWith("VEMPVault: caller is not whitelist");
        });
    });

    describe("Updating Reward Per Block", function () {
        it("Should allow owner to update reward per block", async function () {
            const newRewardPerBlock = ethers.utils.parseEther("2");
            await expect(vempVault.updateRewardPerBlock(newRewardPerBlock))
                .to.emit(vempVault, "RewardPerBlock")
                .withArgs(VEMPPerBlock, newRewardPerBlock);

            expect(await vempVault.VEMPPerBlock()).to.equal(newRewardPerBlock);
        });

        it("Should reject non-owner from updating reward per block", async function () {
            const newRewardPerBlock = ethers.utils.parseEther("2");
            await expect(vempVault.connect(addr2).updateRewardPerBlock(newRewardPerBlock)).to.be.revertedWith("OwnableUnauthorizedAccount");
        });
    });

    describe("Updating Receiver", function () {
        it("Should update receiver correctly", async function () {
            await expect(vempVault.updateReceiver(addr2.address))
                .to.emit(vempVault, "ReceiverUpdated")
                .withArgs(addr1.address, addr2.address);

            expect(await vempVault.receiver()).to.equal(addr2.address);
        });

        it("Should transfer user info to new receiver", async function () {
            await vempVault.updateReceiver(addr2.address);
            const userInfoOld = await vempVault.userInfo(addr1.address);
            const userInfoNew = await vempVault.userInfo(addr2.address);

            expect(userInfoOld.amount).to.equal(0);
            expect(userInfoNew.amount).to.equal(ethers.utils.parseEther("1"));
        });

        it("Should reject updating to zero address or the same receiver", async function () {
            await expect(vempVault.updateReceiver(ethers.constants.AddressZero)).to.be.revertedWith("VEMPVault: Invalid receiver address");
            await expect(vempVault.updateReceiver(addr1.address)).to.be.revertedWith("VEMPVault: Same receiver address");
        });
    });

    describe("Only Owner Can Send Tokens", function () {
        it("Should allow the owner to send ETH to the contract", async function () {
            // Send ETH from the owner to the contract
            const tx = await owner.sendTransaction({
                to: vempVault.address,
                value: ethers.utils.parseEther("1"),
            });

            // Wait for the transaction to be mined
            await tx.wait();

            // Check the contract's balance
            const contractBalance = await ethers.provider.getBalance(vempVault.address);
            expect(contractBalance).to.equal(ethers.utils.parseEther("1"));
        });

        it("Should revert if a non-owner sends ETH to the contract", async function () {
            await expect(
                addr1.sendTransaction({
                    to: vempVault.address,
                    value: ethers.utils.parseEther("1"),
                })
            ).to.be.revertedWith("VEMPVault: Invalid Reward Sender");
        });

        it("Should revert with a custom error message for unauthorized senders", async function () {
            await expect(
                addr2.sendTransaction({
                    to: vempVault.address,
                    value: ethers.utils.parseEther("0.5"),
                })
            ).to.be.revertedWith("VEMPVault: Invalid Reward Sender");
        });
    });
});
