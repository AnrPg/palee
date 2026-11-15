"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useRef, useState, type ReactNode } from "react";

import { CLUBS_KEY, FEED_KEY } from "@/api/community";
import { fetchMyBilling, leaveProvider, MY_BILLING_QUERY_KEY, type BillingProvider } from "@/api/my-billing";
import { fetchFollowStatus, followKey, SOCIAL_KEY, unfollow } from "@/api/social";
import { leaveState, type LeaveState } from "@/components/billing/billing-model";
import { formatDate } from "@/components/finance/MembershipEntitlement";
import { localDay } from "@/components/finance/standing";
import { useSession } from "@/components/session-provider";
import { FollowButton } from "@/components/social/FollowButton";
import { boxChatHref } from "@/components/trials/box-chat-links";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Popover } from "@/components/ui/Popover";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { formatMinorUnits } from "@/lib/finance-accounting";
import { ORGANIZATION_MEMBERSHIPS_KEY } from "@/lib/organization-slug";
import { useMediaQuery } from "@/lib/use-media-query";

/**
 * Leaving a box and unfollowing it where the person meets the box (ANR
 * 2026-11-15 picks, mockups 2026-11-13). Two relations, two buttons: «Μέλος
 * box ▾» (a solo coach: «Προπονείσαι μαζί ▾») opens what the membership is
 * and «Αποχώρηση…»; «Ακολουθείς ▾» is the follow button. The box page also
 * shows them quietly in its Club tab («Η συμμετοχή σου»), Συνδέσεις › Box
 * rows use the same button, and «Οι πληρωμές μου» keeps its own card.
 * Leaving is ADR-595: at once, what stays is listed, following is untouched;
 * the «Έγινε» step offers a quiet «Σταμάτα και να ακολουθείς».
 */

export type ProviderKind = "gym" | "coach";

const DESKTOP_QUERY = "(min-width: 64rem)";

/** The person's billing section for one box (package, money owed, leave facts); null when they have none. */
export function useBoxBilling(slug: string, enabled = true) {
  const token = useSession().tokens?.access_token ?? null;
  const billing = useQuery({
    queryKey: MY_BILLING_QUERY_KEY,
    enabled: Boolean(token) && enabled,
    queryFn: () => fetchMyBilling(token!),
  });
  const provider = billing.data?.providers?.find((entry) => entry.slug === slug) ?? null;
  return { provider, loading: billing.isPending && Boolean(token) && enabled };
}

/** ADR-595 facts for the leave dialog. A member with no billing section bought nothing and owes nothing. */
function leaveFacts(provider: BillingProvider | null, today: string): LeaveState {
  if (!provider) return { kind: "can_leave", packageUntil: null, commitmentUntil: null, owedCents: 0 };
  const state = leaveState(provider, today);
  if (state.kind === "none" && !provider.membership)
    return { kind: "can_leave", packageUntil: null, commitmentUntil: null, owedCents: Math.max(provider.outstanding_cents ?? 0, 0) };
  return state;
}

function ChevronDown() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="m6 9 6 6 6-6" />
    </svg>
  );
}

type BoxFacts = { slug: string; name: string; organizationId: string; kind: ProviderKind };

/**
 * «Μέλος box ▾»: what the membership is (package and its last day, «Οι
 * πληρωμές μου») and «Αποχώρηση από το box…». A sheet on phones, a small
 * popover beside «Μήνυμα» on desktop (pick 8).
 */
export function MembershipButton({ box, short = false, testId = "box-membership" }: { box: BoxFacts; short?: boolean; testId?: string }) {
  const t = useTranslations("BoxRelation");
  const locale = useUiLocale();
  const desktop = useMediaQuery(DESKTOP_QUERY);
  const anchorRef = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const { provider } = useBoxBilling(box.slug, open || leaving);
  const current = provider?.subscriptions?.find((entry) => entry.current) ?? null;
  const label = short ? t("memberShort", { kind: box.kind }) : t("member", { kind: box.kind });

  const panel = (
    <div className="flex flex-col gap-3" data-testid={`${testId}-panel`}>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>
        {current?.package_name
          ? current.ends_on
            ? t("packageUntil", { name: current.package_name, date: formatDate(locale, current.ends_on) })
            : current.package_name
          : t("noPackage")}
      </p>
      <Link
        href={`/me/payments?box=${encodeURIComponent(box.slug)}`}
        className="text-sm font-bold underline-offset-2 hover:underline"
        style={{ color: "var(--primary-strong, var(--primary))" }}
      >
        {t("payments")} ›
      </Link>
      <button
        type="button"
        onClick={() => {
          setOpen(false);
          setLeaving(true);
        }}
        className="flex min-h-11 w-full items-center justify-center rounded-2xl px-4 text-sm font-semibold"
        style={{ border: "1px solid var(--border)", color: "var(--danger)" }}
        data-testid={`${testId}-leave`}
      >
        {t("leave", { kind: box.kind })}
      </button>
    </div>
  );

  return (
    <>
      <button
        ref={anchorRef}
        type="button"
        aria-haspopup="dialog"
        aria-expanded={open}
        onClick={() => setOpen((value) => !value)}
        className="flex min-h-11 shrink-0 items-center gap-1.5 rounded-2xl px-4 text-sm font-bold"
        style={{ background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text)" }}
        data-testid={testId}
      >
        {label}
        <ChevronDown />
      </button>
      {open && desktop ? (
        <Popover anchorRef={anchorRef} open onClose={() => setOpen(false)} role="dialog" ariaLabel={t("menuAria", { name: box.name })} width={300} align="end">
          <div className="p-4">
            <p className="mb-2 text-sm font-extrabold" style={{ color: "var(--text)" }}>{t("member", { kind: box.kind })}</p>
            {panel}
          </div>
        </Popover>
      ) : null}
      {open && !desktop ? (
        <Dialog onClose={() => setOpen(false)} title={t("member", { kind: box.kind })} description={box.name} size="sm">
          {panel}
        </Dialog>
      ) : null}
      {leaving ? <LeaveBoxDialog box={box} provider={provider} onClose={() => setLeaving(false)} /> : null}
    </>
  );
}

/**
 * The Club tab's quiet card «Η συμμετοχή σου» (pick 1, C): the membership
 * with «Αποχώρηση…» and following with its own button.
 */
export function BoxRelationCard({ box, staff }: { box: BoxFacts; staff: boolean }) {
  const t = useTranslations("BoxRelation");
  const locale = useUiLocale();
  const [leaving, setLeaving] = useState(false);
  const { provider } = useBoxBilling(box.slug, !staff);
  const current = provider?.subscriptions?.find((entry) => entry.current) ?? null;

  return (
    <section className="rounded-3xl p-5" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="box-relation-card">
      <h3 className="mb-3 text-sm font-extrabold" style={{ color: "var(--text)" }}>{t("cardTitle")}</h3>
      <div className="flex flex-col gap-4">
        {staff ? null : (
          <Line
            title={t("member", { kind: box.kind })}
            hint={current?.package_name ? (current.ends_on ? t("packageUntil", { name: current.package_name, date: formatDate(locale, current.ends_on) }) : current.package_name) : t("noPackage")}
          >
            <button
              type="button"
              onClick={() => setLeaving(true)}
              className="min-h-10 shrink-0 text-sm font-semibold"
              style={{ color: "var(--danger)" }}
              data-testid="box-relation-card-leave"
            >
              {t("leave", { kind: box.kind })}
            </button>
          </Line>
        )}
        <div className="flex flex-col gap-2">
          <p className="text-xs" style={{ color: "var(--dim)" }}>{t("followHint", { kind: box.kind })}</p>
          <FollowButton targetType="organization" targetId={box.organizationId} quiet wide />
        </div>
      </div>
      {leaving ? <LeaveBoxDialog box={box} provider={provider} onClose={() => setLeaving(false)} /> : null}
    </section>
  );
}

function Line({ title, hint, children }: { title: string; hint: string; children: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <span className="min-w-0">
        <b className="block text-sm" style={{ color: "var(--text)" }}>{title}</b>
        <span className="block text-xs" style={{ color: "var(--dim)" }}>{hint}</span>
      </span>
      {children}
    </div>
  );
}

/**
 * ADR-595's one dialog «Τι μένει», then «Έγινε»: no longer a member, the
 * package's last day, and, while they still follow, a quiet «Σταμάτα και να
 * ακολουθείς» (pick 4; no undo after unfollowing, pick 5). The person's
 * boxes and clubs refresh when the dialog closes, so the page under it
 * stays put until then.
 */
export function LeaveBoxDialog({ box, provider, onClose }: { box: BoxFacts; provider: BillingProvider | null; onClose: () => void }) {
  const t = useTranslations("Billing");
  const tRelation = useTranslations("BoxRelation");
  const ui = useUiTranslations();
  const locale = useUiLocale();
  const token = useSession().tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const [askWhy, setAskWhy] = useState(false);
  const [reason, setReason] = useState("");
  const [today] = useState(() => localDay(new Date()));
  const [facts] = useState(() => leaveFacts(provider, today));
  const [keptUntil, setKeptUntil] = useState<string | null>(null);
  const kind = box.kind;
  const currency = provider?.invoices[0]?.currency ?? provider?.payments[0]?.currency ?? "EUR";

  const leave = useMutation({
    mutationFn: () => leaveProvider(token!, box.slug, reason.trim() || null),
    onSuccess: (result) => setKeptUntil(facts.kind === "can_leave" && facts.packageUntil ? (result.leaving_on?.slice(0, 10) ?? facts.packageUntil) : null),
  });

  async function close() {
    onClose();
    if (leave.isSuccess)
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: MY_BILLING_QUERY_KEY }),
        queryClient.invalidateQueries({ queryKey: ORGANIZATION_MEMBERSHIPS_KEY }),
        queryClient.invalidateQueries({ queryKey: CLUBS_KEY }),
        queryClient.invalidateQueries({ queryKey: SOCIAL_KEY }),
      ]);
  }

  if (leave.isSuccess) {
    return (
      <Dialog
        onClose={() => void close()}
        title={t("leftTitle", { kind })}
        size="sm"
        testId="leave-done"
        footer={<DialogButton tone="primary" onClick={() => void close()} testId="leave-done-ok">{tRelation("done")}</DialogButton>}
      >
        <p className="text-sm" style={{ color: "var(--text)" }}>{t("leftBody", { kind })}</p>
        {keptUntil ? <p className="mt-2 text-sm" style={{ color: "var(--text)" }}>{t("leftPackageUntil", { date: formatDate(locale, keptUntil) })}</p> : null}
        <StopFollowing box={box} />
      </Dialog>
    );
  }

  if (facts.kind !== "can_leave") return null;

  const chatSlug = provider?.contact.box_chat_slug ?? null;
  const stays = [
    facts.packageUntil ? { icon: "🎟️", text: t("leaveKeepsPackage", { date: formatDate(locale, facts.packageUntil) }) } : null,
    facts.commitmentUntil ? { icon: "📅", text: t("leaveKeepsCommitment", { date: formatDate(locale, facts.commitmentUntil) }) } : null,
    facts.owedCents > 0 ? { icon: "💶", text: t("leaveKeepsDebt", { amount: formatMinorUnits(locale, facts.owedCents, currency) }) } : null,
    kind === "gym" ? { icon: "👁️", text: t("leaveKeepsFollow") } : null,
  ].filter((entry): entry is { icon: string; text: string } => entry !== null);
  const listed = facts.packageUntil || facts.commitmentUntil || facts.owedCents > 0;

  return (
    <Dialog
      onClose={onClose}
      title={t("leaveDialogTitle", { kind, name: box.name })}
      size="sm"
      footer={
        <>
          <DialogButton onClick={onClose}>{t("leaveCancel")}</DialogButton>
          <DialogButton tone="danger" disabled={leave.isPending || !token} onClick={() => leave.mutate()} testId="billing-leave-confirm">
            {t("leaveNow")}
          </DialogButton>
        </>
      }
    >
      <p className="text-sm" style={{ color: "var(--text)" }}>{t("leaveNowBody", { kind })}</p>
      {listed ? (
        <div className="mt-3 rounded-xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }} data-testid="billing-leave-stays">
          <p className="text-xs font-semibold" style={{ color: "var(--text-soft)" }}>{t("leaveWhatStays")}</p>
          <ul className="mt-2 flex flex-col gap-2 text-sm" style={{ color: "var(--text)" }}>
            {stays.map((entry) => (
              <li key={entry.icon} className="flex gap-2">
                <span aria-hidden="true">{entry.icon}</span>
                <span className="min-w-0">{entry.text}</span>
              </li>
            ))}
          </ul>
        </div>
      ) : kind === "gym" ? (
        <p className="mt-2 text-xs" style={{ color: "var(--dim)" }}>{t("leaveKeepsFollow")}</p>
      ) : null}
      {askWhy ? (
        <label className="mt-4 block text-xs font-semibold" style={{ color: "var(--text-soft)" }}>
          {t("leaveReason", { kind })}
          <textarea
            autoFocus
            className="mt-1 min-h-20 w-full rounded-xl px-3 py-2 text-sm"
            maxLength={500}
            onChange={(event) => setReason(event.target.value)}
            style={{ background: "var(--panel)", color: "var(--text)", border: "1px solid var(--border)" }}
            value={reason}
          />
        </label>
      ) : (
        <button type="button" className="mt-3 text-xs font-semibold underline" style={{ color: "var(--text-soft)" }} onClick={() => setAskWhy(true)}>
          {t("leaveWhyLink")}
        </button>
      )}
      {chatSlug ? (
        <Link
          href={boxChatHref(chatSlug, "payment")}
          className="mt-4 flex min-h-11 w-full items-center justify-center rounded-2xl px-4 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("leaveContact", { kind })}
        </Link>
      ) : null}
      {leave.isError ? <ErrorNotice variant="field">{localizeError(leave.error, ui)}</ErrorNotice> : null}
    </Dialog>
  );
}

/** «Ακολουθείς ακόμη το box…» with a quiet «Σταμάτα και να ακολουθείς»; afterwards one line, no undo. */
function StopFollowing({ box }: { box: BoxFacts }) {
  const t = useTranslations("BoxRelation");
  const ui = useUiTranslations();
  const token = useSession().tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const key = followKey("organization", box.organizationId);
  const status = useQuery({ queryKey: key, enabled: Boolean(token), queryFn: () => fetchFollowStatus(token!, "organization", box.organizationId) });
  const [stopped, setStopped] = useState(false);
  const stop = useMutation({
    mutationFn: () => unfollow(token!, "organization", box.organizationId),
    onSuccess: async (next) => {
      setStopped(true);
      queryClient.setQueryData(key, next);
      await queryClient.invalidateQueries({ queryKey: FEED_KEY });
    },
  });

  if (stopped)
    return <p className="mt-3 text-sm" style={{ color: "var(--text-soft)" }} data-testid="leave-done-unfollowed">{t("stoppedFollowing", { kind: box.kind })}</p>;
  if (status.data !== "active") return null;
  return (
    <div className="mt-3 rounded-xl p-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("stillFollowing", { kind: box.kind })}</p>
      <button
        type="button"
        disabled={stop.isPending}
        onClick={() => stop.mutate()}
        className="mt-1 min-h-10 text-sm font-semibold underline disabled:opacity-50"
        style={{ color: "var(--text)" }}
        data-testid="leave-done-unfollow"
      >
        {t("stopFollowing")}
      </button>
      {stop.isError ? <ErrorNotice variant="field">{localizeError(stop.error, ui)}</ErrorNotice> : null}
    </div>
  );
}
