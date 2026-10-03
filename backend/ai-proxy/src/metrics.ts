// Observability without PII (BE-10): route, status, latency, provider, model,
// token counts, quota hits and a hashed install id. Never a body, a prompt, an
// image, a food name or an IP address.

export interface MetricEvent {
  route: string;
  status: number;
  latencyMs: number;
  /** A one-way hash of the install id, rotated with the salt. */
  install?: string;
  provider?: string;
  model?: string;
  tokensIn?: number;
  tokensOut?: number;
  reason?: string;
}

export interface Metrics {
  record(event: MetricEvent): void;
}

/** Workers Analytics Engine dataset, when bound. */
export interface AnalyticsDataset {
  writeDataPoint(point: { blobs?: string[]; doubles?: number[]; indexes?: string[] }): void;
}

export class AnalyticsMetrics implements Metrics {
  constructor(private readonly dataset: AnalyticsDataset | undefined, private readonly environment: string) {}

  record(event: MetricEvent): void {
    this.dataset?.writeDataPoint({
      indexes: [event.route],
      blobs: [this.environment, event.provider ?? "", event.model ?? "", event.reason ?? "", event.install ?? ""],
      doubles: [event.status, event.latencyMs, event.tokensIn ?? 0, event.tokensOut ?? 0],
    });
    // Workers Logs keep 7 days on the free plan (doc 07 §4).
    console.log(JSON.stringify({ env: this.environment, ...event }));
  }
}

export class MemoryMetrics implements Metrics {
  readonly events: MetricEvent[] = [];
  record(event: MetricEvent): void {
    this.events.push(event);
  }
}
