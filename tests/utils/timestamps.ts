// timestamps.ts
export class Timestamps {
  public readonly now: number;
  public readonly nowPlus8Days: number;
  public readonly nowPlus33Minutes: number;
  public readonly nowPlus16Minutes: number;
  public readonly DURATIONS_IN_SECONDS = {
    EightDays: 691200,
    OneWeek: 604800,
    SixDays: 518400,
    ThreeDays: 259200,
    OneDay: 86400,
    OneHour: 3600,
    OneMinute: 60,
    OneSecond: 1
  };

  constructor() {
    this.now = Date.now();
    this.nowPlus8Days = Math.floor(this.now / 1000 + this.DURATIONS_IN_SECONDS.EightDays);
    this.nowPlus33Minutes = Math.floor(this.now / 1000 + 33 * this.DURATIONS_IN_SECONDS.OneMinute);
    this.nowPlus16Minutes = Math.floor(this.now / 1000 + 16 * this.DURATIONS_IN_SECONDS.OneMinute);
  }

  public nowPlusDays(days: number): number {
    return Math.floor(this.now / 1000 + days * this.DURATIONS_IN_SECONDS.OneDay);
  }

  public nowMinusDays(days: number): number {
    return Math.floor(this.now / 1000 - days * this.DURATIONS_IN_SECONDS.OneDay);
  }
}
