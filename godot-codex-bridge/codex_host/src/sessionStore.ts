import fs from "node:fs/promises";
import path from "node:path";
import type { HostEvent, HostSession } from "./types.js";

export class SessionStore {
  private readonly events: HostEvent[] = [];

  constructor(
    private readonly stateDir: string,
    private readonly maxReplayEvents: number
  ) {}

  async init(): Promise<void> {
    await fs.mkdir(this.stateDir, { recursive: true });
    await fs.mkdir(path.join(this.stateDir, "events"), { recursive: true });
    await fs.mkdir(path.join(this.stateDir, "threads"), { recursive: true });
    await fs.mkdir(path.join(this.stateDir, "approvals"), { recursive: true });
    await fs.mkdir(path.join(this.stateDir, "background_tasks"), { recursive: true });
    await fs.mkdir(path.join(this.stateDir, "logs"), { recursive: true });
  }

  async saveSession(session: HostSession): Promise<void> {
    await this.init();
    const filePath = path.join(this.stateDir, "sessions.json");
    await fs.writeFile(filePath, `${JSON.stringify(session, null, 2)}\n`, "utf8");
  }

  async appendEvent(event: HostEvent): Promise<void> {
    await this.init();
    this.events.push(event);
    while (this.events.length > this.maxReplayEvents) {
      this.events.shift();
    }
    const eventLog = path.join(this.stateDir, "events", "host-events.jsonl");
    await fs.appendFile(eventLog, `${JSON.stringify(event)}\n`, "utf8");
  }

  replayEvents(): HostEvent[] {
    return [...this.events];
  }
}
