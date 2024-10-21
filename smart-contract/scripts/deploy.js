const { ethers, upgrades } = require("hardhat");

async function main() {
  // Get the Address from Ganache Chain to deploy.
  const [deployer] = await ethers.getSigners();
  console.log("Deployer address", deployer.address);

  // Deploy a mock VEMP token (ERC20)
  // VEMPToken = await ethers.getContractFactory("ERC20Mock");
  // vempToken = await VEMPToken.deploy(deployer.address);
  // await vempToken.deployed();
  // console.log("Test VEMP Token Contract Deployed Address:", vempToken.address);


  // Deploy the VEMPLockContract
  VEMPLockContract = await ethers.getContractFactory("VEMPLockContract");
  vempLockContract = await upgrades.deployProxy(VEMPLockContract, ["", deployer.address]);

  console.log("Lock Contract Deployed Address:", vempLockContract.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
