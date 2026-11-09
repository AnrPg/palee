"use client";

import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useId, useMemo, useState } from "react";

import {
  fetchBoxFollowers,
  fetchFollowerInviteSummary,
  FOLLOWER_INVITE_BATCH_MAX,
  FOLLOWER_INVITE_MESSAGE_MAX,
  FOLLOWER_INVITES_KEY,
  FOLLOWER_INVITES_SUMMARY_KEY,
  followerInvitesListKey,
  inviteFollowers,
  type BoxFollower,
  type FollowerFilter,
  type FollowerInviteOffer,
  type FollowerInviteSendResponse,
} from "@/api/follower-invites";
import { clientErrorMessage } from "@/components/client/errors";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { perLabel } from "@/components/payments/BuyPackageSheet";
import { money } from "@/components/payments/PackageCheckout";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { SPARK_GO_STYLE } from "@/lib/spark";

import { followerRowState, selectableIds, toggleAll } from "./follower-invites";

/**
 * ADR-580 (ANR 2026-11-09, Q1 B): Χρήστες › «N ακόλουθοι δεν είναι ακόμα
 * μέλη». Shown only while someone may be invited. «Δες τους» opens the list:
 * «Προσκάλεσε» on a row invites one person; the check boxes and the bar at
 * the bottom invite many at once (up to 200). Box members never appear.
 */
export function FollowerInvitesCard() {
  const t = useTranslations("UsersDirectory");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const [open, setOpen] = useState(false);
  const summary = useQuery({
    queryKey: FOLLOWER_INVITES_SUMMARY_KEY,
    queryFn: () => fetchFollowerInviteSummary(token).then((response) => response.counts),
    enabled: Boolean(token),
  });
  const counts = summary.data;
  if (!counts || (counts.invitable === 0 && !open)) return null;

  return (
    <section
      aria-labelledby="follower-invites-title"
      className="flex flex-col gap-3 rounded-2xl p-4"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
      data-testid="follower-invites"
    >
      <div className="flex flex-wrap items-center gap-3">
        <div className="min-w-0 flex-1">
          <h2 id="follower-invites-title" className="text-base font-bold" style={{ color: "var(--text)" }}>
            {t("followersTitle", { count: counts.listed })}
          </h2>
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("followersHint")}</p>
        </div>
        <button
          type="button"
          onClick={() => setOpen((value) => !value)}
          aria-expanded={open}
          aria-controls="follower-invites-list"
          className="min-h-11 rounded-xl px-4 text-sm font-bold"
          style={open ? { border: "1px solid var(--border)", color: "var(--text)" } : SPARK_GO_STYLE}
          data-testid="follower-invites-toggle"
        >
          {open ? t("followersHide") : t("followersShow")}
        </button>
      </div>
      {open ? <FollowerList counts={counts} /> : null}
    </section>
  );
}

function FollowerList({ counts }: { counts: { listed: number; trial: number; former: number } }) {
  const t = useTranslations("UsersDirectory");
  const tUi = useUiTranslations();
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const [filter, setFilter] = useState<FollowerFilter>("all");
  const [picked, setPicked] = useState<Set<string>>(() => new Set());
  const [inviting, setInviting] = useState<string[] | null>(null);
  const [result, setResult] = useState<FollowerInviteSendResponse | null>(null);
  const pages = useInfiniteQuery({
    queryKey: followerInvitesListKey(filter),
    queryFn: ({ pageParam }) => fetchBoxFollowers(token, filter, pageParam),
    initialPageParam: null as string | null,
    getNextPageParam: (last) => last.next_cursor ?? null,
    enabled: Boolean(token),
  });
  const rows = useMemo(() => pages.data?.pages.flatMap((page) => page.followers) ?? [], [pages.data]);
  const offer = pages.data?.pages[0]?.offer ?? null;
  const selectable = selectableIds(rows);
  const allPicked = selectable.length > 0 && selectable.every((rowId) => picked.has(rowId));

  function pick(rowId: string) {
    setPicked((current) => {
      const next = new Set(current);
      if (next.has(rowId)) next.delete(rowId);
      else if (next.size < FOLLOWER_INVITE_BATCH_MAX) next.add(rowId);
      return next;
    });
  }

  return (
    <div id="follower-invites-list" className="flex flex-col gap-3">
      <SegmentPicker
        ariaLabel={t("followersFilter")}
        semantics="radiogroup"
        level="sub"
        value={filter}
        onChange={(next) => {
          setFilter(next);
          setPicked(new Set());
        }}
        options={[
          { value: "all", label: t("followersFilterAll"), count: counts.listed },
          { value: "trial", label: t("followersFilterTrial"), count: counts.trial },
          { value: "former", label: t("followersFilterFormer"), count: counts.former },
        ]}
      />
      {result ? (
        <p role="status" className="rounded-xl p-3 text-sm font-semibold" style={{ background: "var(--panel-muted)", color: "var(--text)" }} data-testid="follower-invites-result">
          {t("followersSent", { count: result.sent })}
          {result.skipped.length > 0 ? ` ${t("followersSkipped", { count: result.skipped.length })}` : ""}
        </p>
      ) : null}
      {pages.error ? <ErrorNotice>{clientErrorMessage(pages.error, tUi)}</ErrorNotice> : null}
      {rows.length === 0 && !pages.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("followersEmpty")}</p>
      ) : null}
      {selectable.length > 1 ? (
        <label className="flex min-h-11 cursor-pointer items-center gap-3 text-sm" style={{ color: "var(--text-soft)" }}>
          <input
            type="checkbox"
            checked={allPicked}
            onChange={() => setPicked((current) => toggleAll(current, selectable, FOLLOWER_INVITE_BATCH_MAX))}
            className="h-5 w-5 shrink-0"
            style={{ accentColor: "var(--primary)" }}
            data-testid="follower-invites-all"
          />
          {t("followersPickAll")}
        </label>
      ) : null}
      <ul className="flex flex-col gap-2">
        {rows.map((row) => (
          <FollowerRow
            key={row.person.id}
            row={row}
            picked={picked.has(row.person.id)}
            onPick={() => pick(row.person.id)}
            onInvite={() => setInviting([row.person.id])}
          />
        ))}
      </ul>
      {pages.hasNextPage ? (
        <button
          type="button"
          disabled={pages.isFetchingNextPage}
          onClick={() => void pages.fetchNextPage()}
          className="min-h-11 rounded-xl px-4 text-sm font-semibold disabled:opacity-50"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("followersMore")}
        </button>
      ) : null}
      {picked.size > 0 ? (
        <div
          className="sticky bottom-[calc(var(--bottom-bar-space,0px)+0.5rem)] z-(--z-sticky) flex items-center gap-3 rounded-2xl p-3"
          style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", boxShadow: "var(--shadow-sm)" }}
        >
          <span className="min-w-0 flex-1 text-sm" style={{ color: "var(--text-soft)" }}>
            {t("followersPicked", { count: picked.size })}
          </span>
          <button
            type="button"
            onClick={() => setInviting([...picked])}
            className="min-h-11 rounded-xl px-4 text-sm font-bold"
            style={SPARK_GO_STYLE}
            data-testid="follower-invites-many"
          >
            {t("followersInviteMany", { count: picked.size })}
          </button>
        </div>
      ) : null}
      {inviting && offer ? (
        <InviteSheet
          userIds={inviting}
          name={inviting.length === 1 ? rows.find((row) => row.person.id === inviting[0])?.person.nickname ?? null : null}
          offer={offer}
          onClose={() => setInviting(null)}
          onSent={(response) => {
            setResult(response);
            setPicked(new Set());
            setInviting(null);
          }}
        />
      ) : null}
    </div>
  );
}

function FollowerRow({ row, picked, onPick, onInvite }: { row: BoxFollower; picked: boolean; onPick: () => void; onInvite: () => void }) {
  const t = useTranslations("UsersDirectory");
  const locale = useUiLocale();
  const name = row.person.nickname;
  const state = followerRowState(row);
  const since = new Intl.DateTimeFormat(locale, { dateStyle: "medium" }).format(new Date(row.followed_at));
  const tags = [row.former_member ? t("followersTagFormer") : null, row.had_trial ? t("followersTagTrial") : null].filter(Boolean) as string[];

  return (
    <li className="flex items-center gap-3 rounded-xl p-3" style={{ background: "var(--panel-muted)" }} data-testid="follower-row">
      {state === "invitable" ? (
        <input
          type="checkbox"
          checked={picked}
          onChange={onPick}
          aria-label={t("followersPickNamed", { name })}
          className="h-5 w-5 shrink-0"
          style={{ accentColor: "var(--primary)" }}
        />
      ) : (
        <span aria-hidden="true" className="h-5 w-5 shrink-0" />
      )}
      <PersonAvatar name={name} url={row.person.avatar_url} size={36} />
      <span className="min-w-0 flex-1">
        <span className="flex flex-wrap items-center gap-1.5">
          <span className="truncate text-sm font-bold" style={{ color: "var(--text)" }}>{name}</span>
          {tags.map((tag) => (
            <span key={tag} className="rounded-full px-2 text-[11px] font-semibold" style={{ background: "var(--panel-raised)", color: "var(--text-soft)" }}>
              {tag}
            </span>
          ))}
        </span>
        <span className="block truncate text-xs" style={{ color: "var(--dim)" }}>
          {[row.person.handle ? `@${row.person.handle}` : null, t("followersSince", { date: since })].filter(Boolean).join(" · ")}
        </span>
      </span>
      {state === "invitable" ? (
        <button
          type="button"
          onClick={onInvite}
          className="min-h-10 shrink-0 rounded-xl px-3 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
          aria-label={t("followersInviteNamed", { name })}
          data-testid="follower-invite-one"
        >
          {t("followersInvite")}
        </button>
      ) : (
        <span className="shrink-0 text-end text-xs font-semibold" style={{ color: state === "sent" ? "var(--success)" : "var(--dim)" }}>
          {state === "sent" ? t("followersStateSent") : t("followersStateDeclined")}
        </span>
      )}
    </li>
  );
}

function InviteSheet({
  userIds,
  name,
  offer,
  onClose,
  onSent,
}: {
  userIds: string[];
  name: string | null;
  offer: FollowerInviteOffer;
  onClose: () => void;
  onSent: (response: FollowerInviteSendResponse) => void;
}) {
  const t = useTranslations("UsersDirectory");
  const tPay = useTranslations("Pay");
  const tUi = useUiTranslations();
  const locale = useUiLocale();
  const { tokens } = useSession();
  const queryClient = useQueryClient();
  const messageId = useId();
  const [message, setMessage] = useState("");
  const [packageId, setPackageId] = useState<string | null>(null);
  const [trial, setTrial] = useState(false);
  const send = useMutation({
    mutationFn: () =>
      inviteFollowers(tokens!.access_token, {
        user_ids: userIds,
        message: message.trim() || null,
        package_id: packageId,
        offer_trial: trial,
      }),
    onSuccess: async (response) => {
      await queryClient.invalidateQueries({ queryKey: FOLLOWER_INVITES_KEY });
      onSent(response);
    },
  });

  return (
    <Dialog
      onClose={onClose}
      title={name ? t("followersSheetTitleOne", { name }) : t("followersSheetTitleMany", { count: userIds.length })}
      size="sm"
      variant="sheet"
      testId="follower-invite-sheet"
    >
      <form
        className="flex min-w-0 flex-col gap-4"
        onSubmit={(event) => {
          event.preventDefault();
          send.mutate();
        }}
      >
        <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("followersSheetHint")}</p>
        <div className="flex flex-col gap-1.5">
          <label htmlFor={messageId} className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("followersMessage")}
          </label>
          <textarea
            id={messageId}
            value={message}
            maxLength={FOLLOWER_INVITE_MESSAGE_MAX}
            onChange={(event) => setMessage(event.target.value)}
            rows={3}
            placeholder={t("followersMessagePlaceholder")}
            className="w-full rounded-xl p-3 text-sm"
            style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
            data-testid="follower-invite-message"
          />
        </div>
        {offer.packages.length > 0 ? (
          <fieldset className="flex flex-col gap-1.5">
            <legend className="mb-1.5 text-sm font-semibold" style={{ color: "var(--text)" }}>{t("followersPackage")}</legend>
            {[null, ...offer.packages].map((pkg) => {
              const value = pkg?.id ?? null;
              const selected = packageId === value;
              return (
                <button
                  key={value ?? "none"}
                  type="button"
                  role="radio"
                  aria-checked={selected}
                  onClick={() => setPackageId(value)}
                  className="flex min-h-11 items-center justify-between gap-3 rounded-xl px-3 text-start text-sm"
                  style={{
                    border: `1px solid ${selected ? "var(--primary)" : "var(--border)"}`,
                    boxShadow: selected ? "inset 0 0 0 1px var(--primary)" : undefined,
                    color: "var(--text)",
                  }}
                >
                  <span className="min-w-0 truncate">{pkg ? pkg.name : t("followersPackageNone")}</span>
                  {pkg ? (
                    <span className="shrink-0 tabular-nums" style={{ color: "var(--text-soft)" }}>
                      {money(locale, pkg.price_cents, pkg.currency)}
                      {pkg.billing_period ? ` ${perLabel(tPay, pkg.billing_period)}` : ""}
                    </span>
                  ) : null}
                </button>
              );
            })}
          </fieldset>
        ) : null}
        {offer.trial_available ? (
          <label className="flex min-h-11 cursor-pointer items-center gap-3 text-sm" style={{ color: "var(--text)" }}>
            <input
              type="checkbox"
              checked={trial}
              onChange={() => setTrial((value) => !value)}
              className="h-5 w-5 shrink-0"
              style={{ accentColor: "var(--primary)" }}
            />
            {t("followersTrial")}
          </label>
        ) : null}
        {send.error ? <ErrorNotice>{clientErrorMessage(send.error, tUi)}</ErrorNotice> : null}
        <button
          type="submit"
          disabled={send.isPending}
          className="min-h-12 rounded-2xl px-4 text-base font-extrabold disabled:opacity-50"
          style={SPARK_GO_STYLE}
          data-testid="follower-invite-send"
        >
          {t("followersSend")}
        </button>
      </form>
    </Dialog>
  );
}

