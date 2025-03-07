import 'ethers';
import 'hardhat-deploy';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { owner } = await getNamedAccounts();

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const deployOptions: any = {
    from: owner,
    log: true
  };
  const DeliveryVersusPaymentV1Address = (await deploy('DeliveryVersusPaymentV1', deployOptions)).address;
  console.log(`Transaction sender address      = ${owner}`);
  console.log(`DeliveryVersusPaymentV1 address = ${DeliveryVersusPaymentV1Address}`);
};

export default func;
func.tags = ['DeliveryVersusPaymentV1', 'dvp'];
