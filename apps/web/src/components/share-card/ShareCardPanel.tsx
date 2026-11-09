"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { FEED_KEY, type AttachmentType, type CommunityPost } from "@/api/community";
import { SUMMARY_KEY } from "@/api/social";
import { PALEE_TAGLINE } from "@/components/branding/brand";
import { clientErrorMessage } from "@/components/client/errors";
import { composeTargetGroups, initialComposeTarget, newOperationId, type ComposeTarget } from "@/components/community/community";
import { AudienceSheet } from "@/components/community/ComposeSheet";
import { publishToTarget, rememberedTarget, rememberTarget, targetLabel } from "@/components/community/publish-target";
import { useMyClubs } from "@/components/community/use-community";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { loadPhoto, renderShareCard, shareCardFile, type ShareCardData, type ShareCardFormat, type ShareOutcome } from "@/lib/share-card";

import { uploadCardPhoto } from "./upload-card";

export type CardContent = Omit<ShareCardData, "tagline" | "site">;

export const SHARE_SITE = "palee.app";

const CARD_FILE_NAMES: Record<ShareCardFormat, string> = { story: "palee-story.jpg", square: "palee-square.jpg" };

/**
 * ADR-565 (mockup A, ANR 2026-11-09): the share card of a WOD, a PR or a
 * challenge, Story first or square, with an optional photo behind it.
 * «Μοιράσου» opens the device's share sheet (Instagram, TikTok, Facebook…)
 * and, with «Και στο Palee» (on by default), posts it on Palee too, to the
 * audience of the member's last post. Nothing posts before the tap.
 */
export function ShareCardPanel({
  content,
  attachment,
  organizationId,
  posted,
  onCompose,
  onSendInApp,
  onDone,
}: {
  content: CardContent;
  /** The journal entry the Palee post carries; without one the card itself is the post's photo. */
  attachment?: { type: AttachmentType; id: string } | null;
  /** The box the result belongs to, for the default club channel. */
  organizationId?: string | null;
  /** Already on Palee (auto-post): the checkbox gives way to a note. */
  posted?: { label: string } | null;
  onCompose?: () => void;
  onSendInApp?: () => void;
  onDone: (outcome: ShareOutcome | "skipped") => void;
}) {
  const t = useTranslations("ShareCard");
  const tCommunity = useTranslations("Community");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const clubs = useMyClubs();
  const clubList = useMemo(() => clubs.data ?? [], [clubs.data]);
  const clubId = useMemo(
    () => clubList.find((club) => club.kind === "gym" && club.organization_id === organizationId)?.id ?? null,
    [clubList, organizationId],
  );
  const [chosen, setChosen] = useState<ComposeTarget | null>(null);
  const target = chosen ?? initialComposeTarget(clubList, rememberedTarget(), clubId);
  const [picking, setPicking] = useState(false);
  const [format, setFormat] = useState<ShareCardFormat>("story");
  const [photo, setPhoto] = useState<File | null>(null);
  const [alsoPalee, setAlsoPalee] = useState(true);
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [operationId] = useState(newOperationId);
  const photoInput = useRef<HTMLInputElement>(null);
  // Callers rebuild `content` on every render; the card is redrawn only when what it says changes.
  const contentKey = JSON.stringify(content);
  const data: ShareCardData = useMemo(
    () => ({ ...(JSON.parse(contentKey) as CardContent), tagline: PALEE_TAGLINE, site: SHARE_SITE }),
    [contentKey],
  );

  // The card is drawn ahead of the tap: the share sheet must open inside it.
  useEffect(() => {
    let cancelled = false;
    let url: string | null = null;
    void (async () => {
      try {
        const image = photo ? await loadPhoto(photo) : null;
        const drawn = await renderShareCard(data, format, image, CARD_FILE_NAMES[format]);
        if (cancelled) return;
        url = URL.createObjectURL(drawn);
        setFile(drawn);
        setPreview(url);
      } catch {
        if (!cancelled) setError(t("drawFailed"));
      }
    })();
    return () => {
      cancelled = true;
      if (url) URL.revokeObjectURL(url);
    };
  }, [data, format, photo, t]);

  async function postToPalee(card: File): Promise<CommunityPost | null> {
    if (!token) return null;
    const withCard = Boolean(photo) || !attachment;
    const mediaId = withCard ? await uploadCardPhoto(token, card) : null;
    const post = await publishToTarget(token, clubList, target, {
      attachment_type: attachment?.type,
      attachment_id: attachment?.id,
      media_ids: mediaId ? [mediaId] : undefined,
      client_operation_id: operationId,
    });
    rememberTarget(target);
    await queryClient.invalidateQueries({ queryKey: FEED_KEY });
    if (target.kind === "profile") await queryClient.invalidateQueries({ queryKey: SUMMARY_KEY });
    return post;
  }

  function share() {
    if (!file || busy) return;
    setBusy(true);
    setError(null);
    setStatus(null);
    // Nothing is awaited before the share sheet: browsers allow it only inside the tap.
    const sharing = shareCardFile(file, `${content.title} · ${SHARE_SITE}`);
    const posting = alsoPalee && !posted ? postToPalee(file) : Promise.resolve(null);
    void (async () => {
      const [shared, paleeResult] = await Promise.allSettled([sharing, posting]);
      const outcome = shared.status === "fulfilled" ? shared.value : "cancelled";
      if (paleeResult.status === "rejected") {
        setError(`${t("paleeFailed")} ${clientErrorMessage(paleeResult.reason, tUi)}`);
        setAlsoPalee(true);
      } else if (paleeResult.value) {
        setAlsoPalee(false);
      }
      setStatus(outcome === "downloaded" ? t("downloaded") : outcome === "shared" ? t("shared") : null);
      setBusy(false);
      if (outcome === "shared" && paleeResult.status !== "rejected") onDone(outcome);
    })();
  }

  const label = targetLabel(clubList, target, tCommunity);

  return (
    <div className="flex w-full flex-col gap-3" data-testid="share-card-panel">
      <div className="mx-auto w-full max-w-xs overflow-hidden rounded-3xl" style={{ background: "var(--deep)" }}>
        {preview ? (
          // eslint-disable-next-line @next/next/no-img-element -- a blob: URL drawn in the browser
          <img
            src={preview}
            alt={t("previewAlt")}
            data-testid="share-card-preview"
            data-format={format}
            className="block h-auto w-full"
          />
        ) : (
          <div className="flex aspect-square items-center justify-center text-sm" style={{ color: "var(--deep-contrast)" }}>
            {t("preparing")}
          </div>
        )}
      </div>

      <div className="flex flex-wrap justify-center gap-2" role="group" aria-label={t("formatLabel")}>
        {(["story", "square"] as const).map((value) => (
          <button
            key={value}
            type="button"
            aria-pressed={format === value}
            onClick={() => setFormat(value)}
            className="min-h-10 rounded-full px-4 text-sm font-semibold"
            style={{
              border: `1px solid ${format === value ? "var(--primary)" : "var(--border)"}`,
              color: format === value ? "var(--text)" : "var(--text-soft)",
            }}
          >
            {value === "story" ? t("formatStory") : t("formatSquare")}
          </button>
        ))}
        <button
          type="button"
          aria-pressed={Boolean(photo)}
          onClick={() => (photo ? setPhoto(null) : photoInput.current?.click())}
          className="min-h-10 rounded-full px-4 text-sm font-semibold"
          style={{ border: `1px solid ${photo ? "var(--primary)" : "var(--border)"}`, color: photo ? "var(--text)" : "var(--text-soft)" }}
        >
          {photo ? t("removePhoto") : t("addPhoto")}
        </button>
        <input
          ref={photoInput}
          type="file"
          accept="image/*"
          className="sr-only"
          tabIndex={-1}
          aria-hidden="true"
          data-testid="share-card-photo-input"
          onChange={(event) => {
            const picked = event.target.files?.[0] ?? null;
            event.target.value = "";
            if (picked) setPhoto(picked);
          }}
        />
      </div>

      {posted ? (
        <p role="status" className="rounded-2xl px-3 py-2 text-sm" style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }}>
          {t("postedPalee", { target: posted.label })}
        </p>
      ) : (
        <div className="flex items-center gap-3 rounded-2xl px-3 py-2" style={{ border: "1px solid var(--border)" }}>
          <input
            id="share-card-palee"
            type="checkbox"
            checked={alsoPalee}
            onChange={(event) => setAlsoPalee(event.target.checked)}
          />
          <label htmlFor="share-card-palee" className="flex min-w-0 flex-1 flex-col text-sm">
            <span className="font-semibold" style={{ color: "var(--text)" }}>{t("alsoPalee")}</span>
            <span className="truncate text-xs" style={{ color: "var(--dim)" }}>{label}</span>
          </label>
          <button
            type="button"
            onClick={() => setPicking(true)}
            aria-haspopup="dialog"
            className="min-h-10 shrink-0 rounded-full px-3 text-xs font-semibold"
            style={{ color: "var(--primary)" }}
          >
            {t("change")}
          </button>
        </div>
      )}

      {error ? <ErrorNotice>{error}</ErrorNotice> : null}
      {status ? (
        <p role="status" className="text-center text-sm" style={{ color: "var(--text-soft)" }}>
          {status}
        </p>
      ) : null}

      <button
        type="button"
        onClick={share}
        disabled={!file || busy}
        className="min-h-12 w-full rounded-2xl text-base font-bold disabled:opacity-50"
        style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
      >
        {t("share")}
      </button>
      <div className="flex flex-wrap justify-center gap-x-4 gap-y-1">
        <button type="button" onClick={() => onDone("skipped")} className="min-h-10 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
          {t("notNow")}
        </button>
        {onCompose ? (
          <button type="button" onClick={onCompose} className="min-h-10 text-sm font-semibold" style={{ color: "var(--primary)" }}>
            {t("writePost")}
          </button>
        ) : null}
        {onSendInApp ? (
          <button type="button" onClick={onSendInApp} className="min-h-10 text-sm font-semibold" style={{ color: "var(--primary)" }}>
            {t("sendInApp")}
          </button>
        ) : null}
      </div>

      {picking ? (
        <AudienceSheet
          groups={composeTargetGroups(clubList)}
          selected={target}
          onPick={(value) => {
            setChosen(value);
            setPicking(false);
          }}
          onClose={() => setPicking(false)}
        />
      ) : null}
    </div>
  );
}
