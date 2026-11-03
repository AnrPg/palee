"use client";

// ADR-375: the phone app's `PaleeWatch` plugin (WatchConnectivity on iOS, the
// Wearable Data Layer on Android). The watch talks only to the phone; this
// bridge tells the page whether a watch is detected and connected right now
// and hands it the plan to run. The native plugin is not built yet (see
// ADR-375 «Consequences»), so on the web and in today's store apps
// `watchStatus()` says there is no watch and nothing is offered.
import { hasCapability } from "./index";

export type WatchPlatform = "apple_watch" | "wear_os";

export type WatchStatus = { platform: WatchPlatform; connected: boolean } | null;

export type PaleeWatchPlugin = {
  /** The paired watch with Palee installed, and whether it is reachable now. */
  status(): Promise<{ platform: WatchPlatform | null; reachable: boolean }>;
  /** Puts the execution's timer on the watch (the plugin fetches the watch plan). */
  start(options: { executionId: string }): Promise<void>;
};

let pluginPromise: Promise<PaleeWatchPlugin> | null = null;

function watchPlugin(): Promise<PaleeWatchPlugin> {
  pluginPromise ??= import("@capacitor/core").then(({ registerPlugin }) => registerPlugin<PaleeWatchPlugin>("PaleeWatch"));
  return pluginPromise;
}

/** The watch at this moment; null without the plugin or without a watch. */
export async function watchStatus(): Promise<WatchStatus> {
  if (!hasCapability("watch")) return null;
  try {
    const status = await (await watchPlugin()).status();
    return status.platform ? { platform: status.platform, connected: status.reachable } : null;
  } catch {
    return null;
  }
}

export async function startOnWatch(executionId: string): Promise<boolean> {
  if (!hasCapability("watch")) return false;
  try {
    await (await watchPlugin()).start({ executionId });
    return true;
  } catch {
    return false;
  }
}
