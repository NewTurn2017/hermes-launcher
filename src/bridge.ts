import type { HelperEvent } from "./types";

export type EventListener = (ev: HelperEvent) => void;

/** Abstraction over the Tauri backend so the UI is testable without a webview. */
export interface Bridge {
  /** Run a helper subcommand inside WSL, streaming JSONL events to `onEvent`. */
  runStep(subcommand: string, args: string[], onEvent: EventListener): Promise<void>;
  /** Invoke a one-shot Tauri command (e.g. set_step, save_secret). */
  invoke<T = unknown>(cmd: string, payload?: Record<string, unknown>): Promise<T>;
}

/** In-memory bridge for tests: scripted event streams + stubbed invoke handlers. */
export function makeMockBridge(
  scripts: Record<string, HelperEvent[]> = {},
  handlers: Record<string, (payload?: Record<string, unknown>) => Promise<unknown>> = {},
): Bridge {
  return {
    async runStep(subcommand, _args, onEvent) {
      for (const ev of scripts[subcommand] ?? []) onEvent(ev);
    },
    async invoke<T>(cmd: string, payload?: Record<string, unknown>) {
      const handler = handlers[cmd];
      return (handler ? await handler(payload) : undefined) as T;
    },
  };
}
