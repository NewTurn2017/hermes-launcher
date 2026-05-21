// TS mirror of helper/events.schema.json (Plan 1 contract).
export type Step =
  | "detect"
  | "install-hermes"
  | "codex-login"
  | "slack-manifest"
  | "slack-verify"
  | "write-config"
  | "verify";

export type Level = "recoverable" | "environment" | "fatal";

export type HelperEvent =
  | { event: "step"; step: Step; progress: number; msg: string }
  | {
      event: "detect";
      internet: boolean;
      python3: boolean;
      wslview: boolean;
      cmd_exe: boolean;
      hermes_installed: boolean;
      hpk_installed: boolean;
      codex_installed: boolean;
      codex_authed: boolean;
    }
  | { event: "codex_authed"; email?: string | null }
  | { event: "codex_error"; detail: string }
  | { event: "codex_aborted" }
  | { event: "codex_timeout" }
  | { event: "slack_manifest"; json: string }
  | { event: "slack_verified"; workspace: string; bot: string }
  | { event: "slack_error"; detail: string }
  | { event: "done"; step: Step; ok: boolean }
  | { event: "error"; step: Step; level: Level; detail: string };

const EVENT_NAMES = new Set([
  "step",
  "detect",
  "codex_authed",
  "codex_error",
  "codex_aborted",
  "codex_timeout",
  "slack_manifest",
  "slack_verified",
  "slack_error",
  "done",
  "error",
]);

export function isHelperEvent(x: unknown): x is HelperEvent {
  return (
    typeof x === "object" &&
    x !== null &&
    "event" in x &&
    typeof (x as { event: unknown }).event === "string" &&
    EVENT_NAMES.has((x as { event: string }).event)
  );
}
