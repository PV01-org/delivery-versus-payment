import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';

export const DeliveryVersusPaymentV1HelperV1Module = buildModule('DeliveryVersusPaymentV1HelperV1Module', m => {
  const dvpHelperContract = m.contract('DeliveryVersusPaymentV1HelperV1');
  return { dvpHelperContract };
});
