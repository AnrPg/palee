"use client";

import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import type { ScanRequest, ScanResult } from "@/api/check-in";
import { openDoor, type DoorOpenRequest, type DoorOpenResult } from "@/api/doors";
import type { ScanSource } from "@/components/check-in/check-in";

import { doorAnswer } from "./doors-model";

/**
 * The door opens from the same scan only with the rotating door QR or the
 * NFC tag at the door (never the printed poster, which a photo can share),
 * and only for people of the box: a visitor goes to the desk anyway.
 */
export function opensDoor(source: ScanSource, result: Pick<ScanResult, "outcome">) {
  return (source === "door" || source === "nfc") && result.outcome !== "visitor";
}

/**
 * The door's half of the one answer after the scan (W10 screen 5, option A;
 * ADR-381): «Η πόρτα άνοιξε», or why it did not and what to do (book, the
 * desk), or which door when the branch has two. Offline stays locked.
 */
export function DoorAnswerCard({ token, result, error, body }: { token: string; result: DoorOpenResult | null; error: unknown; body: ScanRequest }) {
  const t = useTranslations("Doors");
  const choose = useMutation({ mutationFn: (doorId: string) => openDoor(token, { ...(body as DoorOpenRequest), door_id: doorId }) });
  const answer = choose.isSuccess || choose.isError ? doorAnswer(choose.data ?? null, choose.error) : doorAnswer(result, error);

  switch (answer.kind) {
    case "none":
      return null;
    case "opened":
      return (
        <Panel tone="success" testId="door-answer-opened">
          <p className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{t("memberOpened")}</p>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("memberOpenedHint", { door: answer.door, seconds: answer.seconds })}</p>
        </Panel>
      );
    case "denied":
      return (
        <Panel tone="warning" testId="door-answer-denied">
          <p className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{t(`memberDenied.${answer.reason}`)}</p>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("memberDeniedHint")}</p>
        </Panel>
      );
    case "offline":
      return (
        <Panel tone="danger" testId="door-answer-offline">
          <p className="text-xl font-extrabold" style={{ color: "var(--text)" }}>{t("memberOffline")}</p>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("memberOfflineHint")}</p>
        </Panel>
      );
    case "choose":
      return (
        <Panel testId="door-answer-choose">
          <p className="text-lg font-extrabold" style={{ color: "var(--text)" }}>{t("memberChoose")}</p>
          <ul className="flex flex-col gap-2">
            {answer.doors.map((door) => (
              <li key={door.id}>
                <button
                  type="button"
                  disabled={choose.isPending}
                  onClick={() => choose.mutate(door.id)}
                  className="flex min-h-12 w-full items-center justify-between rounded-2xl px-4 text-start text-sm font-bold disabled:opacity-60"
                  style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
                >
                  {door.name}
                  <span aria-hidden="true">›</span>
                </button>
              </li>
            ))}
          </ul>
        </Panel>
      );
    case "error":
      return (
        <Panel tone="warning" testId="door-answer-error">
          <p className="text-sm" style={{ color: "var(--text)" }}>{t("memberError")}</p>
        </Panel>
      );
  }
}

function Panel({ tone, testId, children }: { tone?: "success" | "warning" | "danger"; testId: string; children: React.ReactNode }) {
  const color = tone ? `var(--${tone})` : null;
  return (
    <section
      className="flex flex-col gap-2 rounded-3xl p-5"
      style={{
        background: color ? `color-mix(in srgb, ${color} 10%, var(--panel))` : "var(--panel)",
        border: `1px solid ${color ? `color-mix(in srgb, ${color} 45%, transparent)` : "var(--border)"}`,
      }}
      data-testid={testId}
      role="status"
    >
      {children}
    </section>
  );
}
