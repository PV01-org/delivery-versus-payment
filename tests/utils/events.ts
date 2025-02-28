import { ContractTransactionReceipt, EventLog, Log } from 'ethers';

/**
 * Find the first event with the given name in the receipt.
 */
export function findEvent(receipt: ContractTransactionReceipt | null, eventName: string): EventLog {
  return receipt?.logs.find((event: EventLog | Log) => {
    if (event instanceof EventLog) {
      return event.eventName === eventName;
    }
  }) as EventLog;
}

/**
 * Find all events with the given name in the receipt. Returns an empty array if no events are found.
 */
export function findEvents(receipt: ContractTransactionReceipt | null, eventName: string): EventLog[] {
  return receipt?.logs.filter((event: EventLog | Log) => {
    if (event instanceof EventLog) {
      return event.eventName === eventName;
    }
    return false;
  }) as EventLog[];
}
