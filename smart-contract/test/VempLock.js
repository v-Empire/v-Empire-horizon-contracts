const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");

describe("VEMPLockContract", function () {
    let VEMPToken, vempToken, VEMPLockContract, vempLockContract;

    beforeEach(async function () {
        [owner, user1, user2, other] = await ethers.getSigners();

        // Deploy a mock VEMP token (ERC20)
        VEMPToken = await ethers.getContractFactory("ERC20Mock");
        vempToken = await VEMPToken.deploy(owner.address);
        await vempToken.deployed();

        // Deploy the VEMPLockContract
        VEMPLockContract = await ethers.getContractFactory("VEMPLockContract");
        vempLockContract = await upgrades.deployProxy(VEMPLockContract, [vempToken.address, owner.address]);
    });

    describe("Deployment", function () {
        it("should set the correct token and owner addresses", async function () {
            expect(await vempLockContract.vempToken()).to.equal(vempToken.address);
            expect(await vempLockContract.owner()).to.equal(owner.address);
        });
    });

    describe("Locking Tokens", function () {
        it("should allow users to lock tokens", async function () {
            const lockAmount = ethers.utils.parseEther("100");

            // Approve and lock tokens for user1
            await vempToken.connect(user1).approve(vempLockContract.address, lockAmount);
            await vempToken.transfer(user1.address, lockAmount);
            await vempLockContract.connect(user1).lockVEMP(lockAmount);

            // Verify balances and locks
            expect(await vempLockContract.userVEMPLock(user1.address)).to.equal(lockAmount);
            expect(await vempLockContract.totalVempLock()).to.equal(lockAmount);
            expect(await vempToken.balanceOf(vempLockContract.address)).to.equal(lockAmount);
        });

        it("should emit LockVemp event when tokens are locked", async function () {
            const lockAmount = ethers.utils.parseEther("100");

            await vempToken.connect(user1).approve(vempLockContract.address, lockAmount);
            await vempToken.transfer(user1.address, lockAmount);
            await expect(vempLockContract.connect(user1).lockVEMP(lockAmount))
                .to.emit(vempLockContract, "LockVemp")
                .withArgs(user1.address, lockAmount);
        });

        it("should revert if the amount is 0", async function () {
            await expect(vempLockContract.connect(user1).lockVEMP(0)).to.be.revertedWith("VEMPLockContract: Invalid Amount");
        });
    });

    describe("Admin Functions", function () {
        it("should allow the owner to update lock amounts for users", async function () {
            const lockAmounts = [ethers.utils.parseEther("50"), ethers.utils.parseEther("100")];

            await vempLockContract.connect(owner).UpdateUserLockAmount([user1.address, user2.address], lockAmounts);

            expect(await vempLockContract.userVEMPLock(user1.address)).to.equal(lockAmounts[0]);
            expect(await vempLockContract.userVEMPLock(user2.address)).to.equal(lockAmounts[1]);
        });

        it("should revert if array lengths don't match", async function () {
            await expect(vempLockContract.connect(owner).UpdateUserLockAmount([user1.address], [ethers.utils.parseEther("100"), ethers.utils.parseEther("200")]))
                .to.be.revertedWith("VEMPLockContract: Invalid Data");
        });
    });

    describe("Withdraw Tokens by Admin", function () {
        const withdrawAmount = ethers.utils.parseEther("200");

        beforeEach(async function () {
            await vempToken.connect(owner).transfer(vempLockContract.address, withdrawAmount);
        });

        it("should allow the owner to withdraw tokens", async function () {
            const balanceBefore = await vempToken.balanceOf(owner.address);

            await vempLockContract.connect(owner).withdrawTokensByAdmin(owner.address, withdrawAmount);

            expect(await vempToken.balanceOf(owner.address)).to.equal(balanceBefore.add(withdrawAmount));
            expect(await vempLockContract.totalWithdrawTokens()).to.equal(withdrawAmount);
        });

        it("should emit WithdrawTokensByAdmin event when tokens are withdrawn", async function () {
            await expect(vempLockContract.connect(owner).withdrawTokensByAdmin(owner.address, withdrawAmount))
                .to.emit(vempLockContract, "WithdrawTokensByAdmin")
                .withArgs(owner.address, withdrawAmount);
        });

        it("should revert if the amount is invalid", async function () {
            await expect(vempLockContract.connect(owner).withdrawTokensByAdmin(owner.address, 0)).to.be.revertedWith("VEMPLockContract: Invalid Amount");
        });

        it("should revert if the contract has insufficient balance", async function () {
            const excessiveAmount = ethers.utils.parseEther("500");
            await expect(vempLockContract.connect(owner).withdrawTokensByAdmin(owner.address, excessiveAmount)).to.be.revertedWith("VEMPLockContract: Insufficient Balance");
        });
    });
});
