import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';

export const DeliveryVersusPaymentV1Module = buildModule('DeliveryVersusPaymentV1Module', m => {
  const dvpContract = m.contract('DeliveryVersusPaymentV1');
  return { dvpContract };
});
