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
  },
  ERC20: {
    ERC20InsufficientAllowance: 'ERC20InsufficientAllowance',
    ERC20InsufficientBalance: 'ERC20InsufficientBalance'
  },
  ERC721: {
    ERC721NonexistentToken: 'ERC721NonexistentToken',
    ERC721InsufficientApproval: 'ERC721InsufficientApproval'
  }
};
