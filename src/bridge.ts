import { invoke as tauriInvoke, Channel } from "@tauri-apps/api/core";
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

/** Real bridge backed by Tauri `invoke` + `Channel` (used in the packaged app). */
export function makeTauriBridge(): Bridge {
  return {
    async runStep(subcommand, args, onEvent) {
      const channel = new Channel<HelperEvent>();
      channel.onmessage = (msg) => onEvent(msg);
      await tauriInvoke("run_step", { subcommand, args, onEvent: channel });
    },
    invoke<T>(cmd: string, payload?: Record<string, unknown>) {
      return tauriInvoke<T>(cmd, payload);
    },
  };
}
