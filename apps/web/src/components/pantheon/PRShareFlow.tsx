"use client";

import { useState, type ReactNode } from "react";
import { useTranslations } from "next-intl";

import type { PRRecord } from "@/api/gamification";
import { gymClubFor } from "@/components/community/community";
import { ComposeSheet } from "@/components/community/ComposeSheet";
import { Sheet, SheetButton } from "@/components/community/Sheet";
import { useMyClubs } from "@/components/community/use-community";
import { formatScore } from "@/components/pantheon/PantheonCard";
import { ShareCardPanel } from "@/components/share-card/ShareCardPanel";
import { usePrCardContent } from "@/components/share-card/subjects";
import { Dialog } from "@/components/ui/Dialog";

/**
 * After a PR is logged (ADR-157 §8): «Νέο PR!» with «Μοιράσου το», which
 * opens the PR's share card (ADR-565): the device's share sheet and, on by
 * default, a Palee post with the PR attached. «Γράψε ανάρτηση στο Palee»
 * opens compose instead, the media picker first and the box's club as the
 * audience. Nothing posts before a tap on «Μοιράσου» or «Δημοσίευση».
 */
export function PRShareFlow({
  children,
  onClose,
}: {
  children: (onSaved: (pr: PRRecord) => void) => ReactNode;
  onClose: () => void;
}) {
  const [saved, setSaved] = useState<PRRecord | null>(null);
  const [mode, setMode] = useState<"logged" | "card" | "compose">("logged");
  if (saved && mode === "compose") return <SharePRCompose pr={saved} onClose={onClose} />;
  if (saved && mode === "card") return <SharePRCard pr={saved} onCompose={() => setMode("compose")} onClose={onClose} />;
  if (saved) return <PRLoggedSheet pr={saved} onShare={() => setMode("card")} onClose={onClose} />;
  return <>{children(setSaved)}</>;
}

function PRLoggedSheet({ pr, onShare, onClose }: { pr: PRRecord; onShare: () => void; onClose: () => void }) {
  const t = useTranslations("Media");
  return (
    <Sheet
      labelId="pr-logged"
      title={t("prSavedTitle")}
      onClose={onClose}
      footer={
        <>
          <SheetButton onClick={onClose}>{t("prNotNow")}</SheetButton>
          <SheetButton primary onClick={onShare}>{t("prShare")}</SheetButton>
        </>
      }
    >
      <div className="flex flex-col gap-2">
        <p className="text-lg font-bold" style={{ color: "var(--text)" }}>
          {pr.name} · <span className="tabular-nums">{formatScore(Number(pr.current_score), pr.unit)}</span>
        </p>
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("prSavedBody")}</p>
      </div>
    </Sheet>
  );
}

function SharePRCompose({ pr, onClose }: { pr: PRRecord; onClose: () => void }) {
  const clubs = useMyClubs();
  if (!clubs.isSuccess && !clubs.isError) return null;
  const list = clubs.data ?? [];
  const club = gymClubFor(list, pr.organization_id ?? null);
  return <ComposeSheet clubs={list} clubId={club?.id ?? null} initialAttachment={{ type: "pr", id: pr.id }} onClose={onClose} />;
}

function SharePRCard({ pr, onCompose, onClose }: { pr: PRRecord; onCompose: () => void; onClose: () => void }) {
  const t = useTranslations("ShareCard");
  const content = usePrCardContent(pr);
  return (
    <Dialog onClose={onClose} title={t("title")} size="md">
      <ShareCardPanel
        content={content}
        attachment={{ type: "pr", id: pr.id }}
        organizationId={pr.organization_id ?? null}
        onCompose={onCompose}
        onDone={onClose}
      />
    </Dialog>
  );
}
