// This setup uses Hardhat Ignition to manage smart contract deployments.
// Learn more about it at https://hardhat.org/ignition

import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const LockModule = buildModule("LockModule", (m) => {

  const factory = m.contract("Factory");
  const streamPayToken = m.contract("StreamPayToken");

  return { factory };
});

export default LockModule;
