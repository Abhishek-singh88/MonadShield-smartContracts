const { ethers } = require("hardhat");

async function main() {
  console.log("🚀 Deploying MonadShield AutoRevoker to Monad testnet...");
  
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  console.log("Account balance:", ethers.utils.formatEther(await deployer.getBalance()));

  // Deploy AutoRevoker
  console.log("\nDeploying AutoRevoker contract...");
  const AutoRevoker = await ethers.getContractFactory("AutoRevoker");
  const autoRevoker = await AutoRevoker.deploy();
  
  await autoRevoker.deployed();
  
  console.log("AutoRevoker deployed to:", autoRevoker.address);
  console.log("Transaction hash:", autoRevoker.deployTransaction.hash);
  
  // Test basic functionality
  console.log("\n Testing basic functionality...");
  try {
    const stats = await autoRevoker.getStats();
    console.log("Initial delegations:", stats.totalDelegations.toString());
    console.log("Initial revocations:", stats.totalRevocations.toString());
    console.log("Contract paused:", stats.contractPaused);
    console.log("Contract is working!");
  } catch (error) {
    console.log("Contract test failed:", error.message);
  }
  
  console.log("\n🎉 Deployment completed successfully!");
  
  return autoRevoker.address;
}

main()
  .then((contractAddress) => {
    console.log("\n🎯 Contract Address:", contractAddress);
    process.exit(0);
  })
  .catch((error) => {
    console.error("❌ Deployment failed:", error);
    process.exit(1);
  });
