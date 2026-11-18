// Deploys AgentBoard pointing at the official SPACE ID Agent ID collection.
// Mainnet Agent ID: 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F (BNB Chain, 56)
const { ethers, network } = require("hardhat");

const AGENT_ID_MAINNET = "0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F";

async function main() {
  const agentId = process.env.AGENT_ID_ADDRESS || AGENT_ID_MAINNET;
  const [deployer] = await ethers.getSigners();
  console.log("Network:", network.name, "chainId:", network.config.chainId);
  console.log("Deployer:", deployer.address);
  console.log("Agent ID collection:", agentId);

  const Board = await ethers.getContractFactory("AgentBoard");
  const board = await Board.deploy(agentId);
  await board.waitForDeployment();
  const address = await board.getAddress();
  console.log("AgentBoard deployed to:", address);
  console.log("Verify with:");
  console.log(`  npx hardhat verify --network ${network.name} ${address} ${agentId}`);
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
