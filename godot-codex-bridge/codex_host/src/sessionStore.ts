import path from "node:path";
import { appendFileInsideRootSync, ensureDirectoryInsideRootSync, writeFileInsideRootSync } from "./physicalPath.js";
import type { HostEvent, HostSession } from "./types.js";

export class SessionStore {
  private readonly events: HostEvent[] = [];
  private initPromise: Promise<void> | null = null;
  private eventWriteTail: Promise<void> = Promise.resolve();

  constructor(
    private readonly stateDir: string,
    private readonly maxReplayEvents: number,
    private readonly physicalRoot: string = path.dirname(stateDir),
  ) {}

  async init(): Promise<void> {
    this.initPromise ??= Promise.resolve().then(() => {
      ensureDirectoryInsideRootSync(this.physicalRoot, this.stateDir);
      ensureDirectoryInsideRootSync(this.physicalRoot, path.join(this.stateDir, "events"));
      ensureDirectoryInsideRootSync(this.physicalRoot, path.join(this.stateDir, "threads"));
      ensureDirectoryInsideRootSync(this.physicalRoot, path.join(this.stateDir, "approvals"));
      ensureDirectoryInsideRootSync(this.physicalRoot, path.join(this.stateDir, "background_tasks"));
      ensureDirectoryInsideRootSync(this.physicalRoot, path.join(this.stateDir, "logs"));
    });
    await this.initPromise;
  }

  async saveSession(session: HostSession): Promise<void> {
    await this.init();
    const filePath = path.join(this.stateDir, "sessions.json");
    writeFileInsideRootSync(this.physicalRoot, filePath, `${JSON.stringify(session, null, 2)}\n`);
  }

  async appendEvent(event: HostEvent): Promise<void> {
    await this.init();
    this.events.push(event);
    while (this.events.length > this.maxReplayEvents) {
      this.events.shift();
    }
    const eventLog = path.join(this.stateDir, "events", "host-events.jsonl");
    const write = this.eventWriteTail.then(() => {
      appendFileInsideRootSync(this.physicalRoot, eventLog, `${JSON.stringify(event)}\n`);
    });
    this.eventWriteTail = write.catch(() => undefined);
    await write;
  }

  replayEvents(): HostEvent[] {
    return [...this.events];
  }
}
