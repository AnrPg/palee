"use client";

import { useUiTranslations } from "@/i18n/ui";
import React, { createContext, useContext, useState, type ReactNode } from "react";

import type { ClassTimerCommand } from "@/api/class-timers";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { MoreMenu, type MoreMenuItem } from "@/components/ui/MoreMenu";
import { formatClock } from "@/components/workouts/execution/TimerDisplay";
import { useClassTimer } from "@/hooks/useClassTimer";
import { useClassTimerCues } from "@/hooks/useClassTimerCues";
import { useScreenWakeLock } from "@/hooks/useScreenWakeLock";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";
import { segmentLabel } from "@/lib/segment-label";
import { type CueMode, primeCueAudio, readCueMode, storeCueMode } from "@/lib/timer-cues";

import { ClassScreenPin } from "./ClassScreenPin";
import { ClassTimerChooser } from "./ClassTimerChooser";
import { ClassTimerFace } from "./ClassTimerFace";
import { TimerNowPanel, useTimerNow } from "./TimerNowPanel";

const COUNTDOWN_CHOICES = [0, 5, 10, 15];

// ANR 2026-11-04 (mockups: layout B, help B): the coach's phone shows only the
// controls that work right now (nothing greyed out), the playback controls stay
// in a dock at the bottom within thumb reach, and «?» shows a short caption
// under every control explaining what it does.

/** Whether «?» captions are showing. */
const HelpContext = createContext(false);

/** A caption under a control, shown while «?» is on. */
export function HelpCaption({ children, id }: { children: ReactNode; id?: string }) {
  const on = useContext(HelpContext);
  if (!on) return null;
  return (
    <span id={id} data-testid="remote-help" className="mt-0.5 block text-xs font-medium leading-snug" style={{ opacity: 0.8 }}>
      {children}
    </span>
  );
}

/** The coach's remote: drives the class timer every screen in the room follows. */
export function ClassTimerControl({ slotId }: { slotId: string }) {
  const i18n = useUiTranslations();
  const { tokens } = useSession();
  const organizationSlug = useOrganizationSlug();
  const timer = useClassTimer(tokens?.access_token, slotId);
  const [countdown, setCountdown] = useState(10);
  const [cueMode, setCueMode] = useState<CueMode>(() => readCueMode());
  const [help, setHelp] = useState(false);
  const [wallOpen, setWallOpen] = useState(false);
  const [confirmReset, setConfirmReset] = useState(false);

  useScreenWakeLock(timer.position?.status === "running");
  useClassTimerCues(timer.position, cueMode);
  const now = useTimerNow(timer.payload ?? null, timer.position);

  const displayHref = adminHref(`/class-timer/${slotId}/display`, organizationSlug);

  function run(command: ClassTimerCommand) {
    primeCueAudio();
    void timer.send(command);
  }

  if (!timer.payload) {
    return (
      <div className="flex min-h-dvh items-center justify-center px-6 text-center" style={{ background: "var(--bg)", color: "var(--muted)" }}>
        {timer.loadError ? i18n("classTimerUnavailable") : i18n("kpiLoading")}
      </div>
    );
  }

  const { payload, position } = timer;
  const status = position?.status ?? payload.timer.status;
  const between = status === "ready" || status === "finished";
  const hasTimer = payload.segments.length > 0;
  const index = position?.index ?? payload.timer.current_segment_index ?? 0;
  const first = index <= 0;
  const last = index >= payload.segments.length - 1;
  const current = position?.segment ?? null;
  const adjustable =
    current && typeof current.duration_seconds === "number" && (current.kind === "countdown" || current.kind === "countup");
  const problemText =
    timer.problem === "conflict"
      ? i18n("classTimerConflict")
      : timer.problem === "forbidden"
        ? i18n("classTimerForbidden")
        : timer.problem === "rejected"
          ? i18n("classTimerRejected")
          : timer.problem === "offline"
            ? i18n("classTimerOffline")
            : null;

  const moreItems: MoreMenuItem[] = [];
  if (!between && !last) {
    moreItems.push({ label: i18n("classTimerFinish"), hint: i18n("classTimerFinishHelp"), onSelect: () => run({ command: "finish" }), disabled: timer.sending, testId: "remote-finish" });
  }
  if (status !== "ready") {
    moreItems.push({
      label: i18n("classTimerReset"),
      hint: i18n("classTimerResetHelp"),
      tone: "danger",
      disabled: timer.sending,
      testId: "remote-reset",
      // Reset clears the clock on every screen in the room: ask first while a class is under way.
      onSelect: () => (between ? run({ command: "reset" }) : setConfirmReset(true)),
    });
  }

  return (
    <HelpContext.Provider value={help}>
      <main className="flex min-h-dvh flex-col" style={{ background: "var(--bg)", color: "var(--text)" }}>
        <div className="mx-auto w-full max-w-3xl flex-1 space-y-4 px-4 py-5">
          <header className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="text-xs font-bold uppercase tracking-[0.2em]" style={{ color: "var(--primary)" }}>
                {i18n("classTimerRemoteTitle")}
              </p>
              <h1 className="truncate text-2xl font-black">{payload.workout?.title ?? payload.class.name}</h1>
              <p className="flex flex-wrap items-center gap-2 text-sm" style={{ color: "var(--muted)" }}>
                <span className="min-w-0 truncate">{payload.class.name}</span>
                <ConnectionChip connected={timer.connected} />
              </p>
              <HelpCaption>{timer.connected ? i18n("classTimerLiveHelp") : i18n("classTimerReconnectingHelp")}</HelpCaption>
            </div>
            <div className="flex shrink-0 gap-1.5">
              <IconButton label={i18n("classTimerHelpToggle")} pressed={help} onClick={() => setHelp((value) => !value)} testId="remote-help-toggle">
                <HelpIcon />
              </IconButton>
              <IconButton label={i18n("classTimerWallScreen")} onClick={() => setWallOpen(true)} testId="remote-wall-screen">
                <ScreenIcon />
              </IconButton>
              <IconButton
                label={cueMode === "off" ? i18n("classTimerSoundOff") : i18n("classTimerSoundOn")}
                pressed={cueMode !== "off"}
                testId="remote-sound"
                onClick={() => {
                  const next: CueMode = cueMode === "off" ? "sound" : "off";
                  setCueMode(next);
                  storeCueMode(next);
                  primeCueAudio();
                }}
              >
                {cueMode === "off" ? <BellOffIcon /> : <BellIcon />}
              </IconButton>
            </div>
          </header>

          {help ? (
            <ul className="grid gap-1 rounded-2xl px-4 py-3 text-xs" style={{ background: "var(--panel-muted)", color: "var(--text-soft)" }} data-testid="remote-help-header">
              <li>
                <strong>{i18n("classTimerWallScreen")}:</strong> {i18n("classTimerWallScreenHelp")}
              </li>
              <li>
                <strong>{cueMode === "off" ? i18n("classTimerSoundOff") : i18n("classTimerSoundOn")}:</strong> {i18n("classTimerSoundHelp")}
              </li>
            </ul>
          ) : null}

          <section className="rounded-3xl border p-5" style={{ borderColor: "var(--border)", background: "var(--panel)" }}>
            <ClassTimerFace payload={payload} position={position} size="panel" />
            <p className="text-center text-sm" style={{ color: "var(--muted)" }}>
              <HelpCaption>{i18n("classTimerClockHelp")}</HelpCaption>
            </p>
            {now ? (
              <TimerNowPanel now={now} size="panel" style={{ marginTop: "1rem", paddingTop: "1rem", borderTop: "1px solid var(--border)" }} />
            ) : null}
          </section>

          {problemText && timer.problem !== "conflict" ? <ErrorNotice>{problemText}</ErrorNotice> : null}
          {problemText && timer.problem === "conflict" ? (
            <p role="alert" className="rounded-2xl px-4 py-3 text-sm" style={{ background: "color-mix(in srgb, var(--warning) 14%, transparent)", color: "var(--text)" }}>
              {problemText}
            </p>
          ) : null}

          {hasTimer && between ? (
            <section className="rounded-3xl border p-5" style={{ borderColor: "var(--border)", background: "var(--panel)" }}>
              <h2 className="text-base font-black">{i18n("classTimerGetReadyLabel")}</h2>
              <p className="text-sm" style={{ color: "var(--muted)" }}>
                <HelpCaption>{i18n("classTimerCountdownHelp")}</HelpCaption>
              </p>
              <div role="group" aria-label={i18n("classTimerGetReadyLabel")} className="mt-3 flex flex-wrap gap-2">
                {COUNTDOWN_CHOICES.map((seconds) => (
                  <button
                    key={seconds}
                    type="button"
                    aria-pressed={countdown === seconds}
                    onClick={() => setCountdown(seconds)}
                    className="min-h-10 whitespace-nowrap rounded-full px-4 text-sm font-semibold tabular-nums"
                    style={
                      countdown === seconds
                        ? { background: "var(--primary)", color: "var(--primary-contrast)" }
                        : { border: "1px solid var(--border)", color: "var(--text-soft)" }
                    }
                  >
                    {seconds === 0 ? i18n("classTimerCountdownNone") : i18n("classTimerCountdownSeconds", { seconds })}
                  </button>
                ))}
              </div>
            </section>
          ) : null}

          {between ? (
            <ClassTimerChooser
              key={hasTimer ? "other" : "choose"}
              hasTimer={hasTimer}
              hasWorkout={Boolean(payload.workout)}
              presetActive={Boolean(payload.timer.timer_preset)}
              sending={timer.sending}
              onConfigure={(preset) => run({ command: "configure", timer_preset: preset })}
            />
          ) : null}

          {payload.segments.length > 1 ? (
            <details className="group rounded-3xl border" style={{ borderColor: "var(--border)", background: "var(--panel)" }} data-testid="remote-segments">
              <summary className="flex min-h-12 cursor-pointer list-none items-center justify-between gap-3 px-5 text-base font-black">
                {i18n("classTimerJumpTitle")}
                <span aria-hidden="true" className="transition-transform group-open:rotate-180">▾</span>
              </summary>
              <div className="px-5 pb-4">
                <p className="text-sm" style={{ color: "var(--muted)" }}>
                  <HelpCaption>{i18n("classTimerJumpHelp")}</HelpCaption>
                </p>
                <ol className="mt-2 max-h-80 space-y-1 overflow-y-auto">
                  {payload.segments.map((segment, segmentIndex) => {
                    const active = position?.index === segmentIndex && !between;
                    return (
                      <li key={segment.segment_key}>
                        <button
                          type="button"
                          disabled={timer.sending}
                          aria-current={active || undefined}
                          onClick={() => run({ command: "jump", index: segmentIndex })}
                          className="flex min-h-11 w-full items-center justify-between gap-3 rounded-xl px-3 text-start text-sm disabled:opacity-40"
                          style={active ? { background: "color-mix(in srgb, var(--primary) 18%, transparent)", fontWeight: 700 } : { color: "var(--text-soft)" }}
                        >
                          <span className="min-w-0 truncate">
                            {segmentIndex + 1}. {segment.section_name ? `${segment.section_name} · ` : ""}
                            {segmentLabel(segment, i18n)}
                          </span>
                          {segment.duration_seconds ? <span className="shrink-0 font-mono tabular-nums">{formatClock(segment.duration_seconds)}</span> : null}
                        </button>
                      </li>
                    );
                  })}
                </ol>
              </div>
            </details>
          ) : null}
        </div>

        {hasTimer ? (
          <section
            aria-label={i18n("classTimerControlsLabel")}
            data-testid="remote-dock"
            className="sticky bottom-0 border-t"
            style={{
              borderColor: "var(--border)",
              background: "var(--panel)",
              paddingBottom: "max(0.75rem, env(safe-area-inset-bottom, 0px))",
            }}
          >
            <div className="mx-auto grid w-full max-w-3xl gap-2 px-4 pt-3">
              <div className="flex gap-2">
                {between ? (
                  <PrimaryButton
                    disabled={timer.sending}
                    onClick={() => run({ command: "start", countdown_seconds: countdown })}
                    label={status === "finished" ? i18n("classTimerStartAgain") : i18n("start952f375")}
                    help={i18n("classTimerStartHelp")}
                  />
                ) : status === "running" ? (
                  <PrimaryButton disabled={timer.sending} onClick={() => run({ command: "pause" })} label={i18n("pausecd21a1b")} help={i18n("classTimerPauseHelp")} />
                ) : (
                  <PrimaryButton disabled={timer.sending} onClick={() => run({ command: "resume" })} label={i18n("resumeb3bd0b5")} help={i18n("classTimerResumeHelp")} />
                )}
                {between && moreItems.length > 0 ? <DockMore items={moreItems} label={i18n("classTimerMore")} /> : null}
              </div>

              {!between && adjustable ? (
                <div>
                  <div className="grid grid-cols-2 gap-2">
                    <ControlButton label={i18n("minusThirtySecondsLabel")} disabled={timer.sending} onClick={() => run({ command: "adjust", delta_seconds: -30 })} />
                    <ControlButton label={i18n("plusThirtySecondsLabel")} disabled={timer.sending} onClick={() => run({ command: "adjust", delta_seconds: 30 })} />
                  </div>
                  <p className="text-center" style={{ color: "var(--muted)" }}>
                    <HelpCaption>{i18n("classTimerAdjustHelp")}</HelpCaption>
                  </p>
                </div>
              ) : null}

              {!between ? (
                <div className="flex gap-2">
                  <ControlButton
                    label={first ? i18n("classTimerRestart") : i18n("backc32ae9f")}
                    help={first ? i18n("classTimerRestartHelp") : i18n("classTimerBackHelp")}
                    disabled={timer.sending}
                    onClick={() => run({ command: "previous" })}
                  />
                  <ControlButton
                    label={last ? i18n("classTimerComplete") : i18n("nextbc98198")}
                    help={last ? i18n("classTimerCompleteHelp") : i18n("classTimerNextHelp")}
                    disabled={timer.sending}
                    onClick={() => run({ command: "next" })}
                  />
                  <DockMore items={moreItems} label={i18n("classTimerMore")} />
                </div>
              ) : null}
            </div>
          </section>
        ) : null}
      </main>

      {wallOpen ? (
        <Dialog
          title={i18n("classTimerWallScreen")}
          description={i18n("classTimerWallScreenHelp")}
          size="md"
          variant="sheet"
          testId="remote-wall-dialog"
          onClose={() => setWallOpen(false)}
        >
          <WallScreenActions href={displayHref} token={tokens?.access_token} slotId={slotId} />
        </Dialog>
      ) : null}

      {confirmReset ? (
        <Dialog
          title={i18n("classTimerResetConfirmTitle")}
          description={i18n("classTimerResetConfirmBody")}
          size="sm"
          testId="remote-reset-dialog"
          onClose={() => setConfirmReset(false)}
          footer={
            <>
              <DialogButton onClick={() => setConfirmReset(false)}>{i18n("cancel")}</DialogButton>
              <DialogButton
                tone="danger"
                testId="remote-reset-confirm"
                onClick={() => {
                  setConfirmReset(false);
                  run({ command: "reset" });
                }}
              >
                {i18n("classTimerReset")}
              </DialogButton>
            </>
          }
        >
          {null}
        </Dialog>
      ) : null}
    </HelpContext.Provider>
  );
}

/** Copy the wall screen's link, pin the class on a box screen, or open it here. */
function WallScreenActions({ href, token, slotId }: { href: string; token: string | undefined; slotId: string }) {
  const i18n = useUiTranslations();
  const [copied, setCopied] = useState(false);
  const rowClass = "flex min-h-14 w-full flex-col justify-center rounded-2xl px-4 py-2.5 text-start text-sm font-bold";
  const rowStyle = { border: "1px solid var(--border)", color: "var(--text)", background: "var(--panel)" };

  async function copy() {
    try {
      await navigator.clipboard.writeText(new URL(href, window.location.origin).toString());
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2_000);
    } catch {
      setCopied(false);
    }
  }

  return (
    <div className="grid gap-2">
      <button type="button" onClick={() => void copy()} className={rowClass} style={rowStyle} data-testid="remote-copy-link">
        <span>{copied ? i18n("classTimerLinkCopied") : i18n("classTimerCopyLink")}</span>
        <Hint>{i18n("classTimerCopyLinkHelp")}</Hint>
      </button>
      <ClassScreenPin token={token} slotId={slotId} className={rowClass} style={rowStyle} hint={<Hint>{i18n("classTimerOnScreenHelp")}</Hint>} />
      <a href={href} target="_blank" rel="noopener" className={rowClass} style={rowStyle} data-testid="remote-open-display">
        <span>{i18n("classTimerOpenHere")}</span>
        <Hint>{i18n("classTimerOpenHereHelp")}</Hint>
      </a>
    </div>
  );
}

function Hint({ children }: { children: ReactNode }) {
  return (
    <span className="mt-0.5 block text-xs font-normal" style={{ color: "var(--muted)" }}>
      {children}
    </span>
  );
}

function ConnectionChip({ connected }: { connected: boolean }) {
  const i18n = useUiTranslations();
  const tone = connected ? "var(--success)" : "var(--warning)";
  return (
    <span
      data-testid="remote-connection"
      className="inline-flex shrink-0 items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-bold"
      style={{ color: tone, background: `color-mix(in srgb, ${tone} 14%, transparent)` }}
    >
      <span aria-hidden="true" className="h-1.5 w-1.5 rounded-full" style={{ background: tone }} />
      {connected ? i18n("classTimerLive") : i18n("classTimerReconnecting")}
    </span>
  );
}

function IconButton({ label, pressed, onClick, testId, children }: { label: string; pressed?: boolean; onClick: () => void; testId: string; children: ReactNode }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      aria-pressed={pressed}
      onClick={onClick}
      data-testid={testId}
      className="grid h-11 w-11 place-items-center rounded-2xl"
      style={
        pressed
          ? { background: "color-mix(in srgb, var(--primary) 16%, transparent)", color: "var(--primary)" }
          : { border: "1px solid var(--border)", color: "var(--text-soft)", background: "var(--panel)" }
      }
    >
      {children}
    </button>
  );
}

function PrimaryButton({ label, help, disabled, onClick }: { label: string; help: string; disabled: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="min-h-16 flex-1 rounded-2xl px-4 py-2 text-xl font-black disabled:opacity-40"
      style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
    >
      {label}
      <HelpCaption>{help}</HelpCaption>
    </button>
  );
}

function ControlButton({ label, help, disabled, onClick }: { label: string; help?: string; disabled: boolean; onClick: () => void }) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onClick}
      className="min-h-14 flex-1 rounded-2xl px-3 py-2 text-base font-bold disabled:opacity-40"
      style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
    >
      {label}
      {help ? <HelpCaption>{help}</HelpCaption> : null}
    </button>
  );
}

function DockMore({ items, label }: { items: MoreMenuItem[]; label: string }) {
  const help = useContext(HelpContext);
  if (items.length === 0) return null;
  return <MoreMenu label={label} items={items} variant="tile" testId="remote-more" showHints={help} />;
}

const iconProps = {
  width: 20,
  height: 20,
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 2,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  "aria-hidden": true,
};

function HelpIcon() {
  return (
    <svg {...iconProps}>
      <circle cx="12" cy="12" r="10" />
      <path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3" />
      <path d="M12 17h.01" />
    </svg>
  );
}

function ScreenIcon() {
  return (
    <svg {...iconProps}>
      <rect x="3" y="5" width="18" height="12" rx="2" />
      <path d="M8 21h8M12 17v4" />
    </svg>
  );
}

function BellIcon() {
  return (
    <svg {...iconProps}>
      <path d="M6 8a6 6 0 1 1 12 0c0 7 3 9 3 9H3s3-2 3-9" />
      <path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" />
    </svg>
  );
}

function BellOffIcon() {
  return (
    <svg {...iconProps}>
      <path d="M6 8a6 6 0 0 1 9.3-5" />
      <path d="M18 8c0 7 3 9 3 9H9" />
      <path d="M6 8c0 4-1 6.5-2 7.7" />
      <path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" />
      <path d="m2 2 20 20" />
    </svg>
  );
}

