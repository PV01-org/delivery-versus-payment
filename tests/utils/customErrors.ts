export const CUSTOM_ERRORS = {
  DeliveryVersusPayment: {
    ApprovalAlreadyGranted: 'ApprovalAlreadyGranted',
    ApprovalNotGranted: 'ApprovalNotGranted',
    CallerNotInvolved: 'CallerNotInvolved',
    CannotSendEtherDirectly: 'CannotSendEtherDirectly',
    CutoffDatePassed: 'CutoffDatePassed',
    IncorrectETHAmount: 'IncorrectETHAmount',
    InvalidERC20Token: 'InvalidERC20Token',
    InvalidERC721Token: 'InvalidERC721Token',
    NoETHToWithdraw: 'NoETHToWithdraw',
    NoFlowsProvided: 'NoFlowsProvided',
    ReentrancyGuardReentrantCall: 'ReentrancyGuardReentrantCall',
    SettlementAlreadyExecuted: 'SettlementAlreadyExecuted',
    SettlementDoesNotExist: 'SettlementDoesNotExist',
    SettlementNotApproved: 'SettlementNotApproved'
  },
  DeliveryVersusPaymentHelper: {
    InvalidPageSize: 'InvalidPageSize'
  }
};
