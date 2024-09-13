const { ethers } = require("hardhat");

module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  console.log(`Network invoked is : =>  ${hre.network.name}`);
  const VRF_COORDINATOR_ID = process.env.VRF_COORDINATOR_ID;
  const SUBSCRIPTION_ID = process.env.SUBSCRIPTION_ID;
  const KEY_HASH = process.env.KEY_HASH;

  if (!VRF_COORDINATOR_ID){
    console.warn(
      `Missing VRF_COORDINATOR_ID in .env file`
    );
  }

  if (!SUBSCRIPTION_ID){
    console.warn(
      `Missing SUBSCRIPTION_ID in .env file`
    );
  }

  if (!KEY_HASH){
    console.warn(
      `Missing KEY_HASH in .env file`
    );
  }

  const REQUEST_CONFIRMATIONS_BLOCKS = 3;
  const GAME_DURATION = 60 * 60 * 24; // 1-day
  const PARTICIPATION_FEE = ethers.parseEther("0.1");

  const treasureHunt = await deploy("TreasureHunt", {
    from: deployer,
    args: [
      REQUEST_CONFIRMATIONS_BLOCKS,
      GAME_DURATION,
      SUBSCRIPTION_ID,
      PARTICIPATION_FEE,
      KEY_HASH,
      VRF_COORDINATOR_ID,
    ],
    log: true,
    deterministicDeployment: true,
  });
};

module.exports.tags = ["TreasureHunt"];
