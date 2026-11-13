"use client";

import Link from "next/link";
import { useTranslations } from "next-intl";

import type { BoxJoinStatus } from "@/api/social";
import { SPARK_GO_STYLE } from "@/lib/spark";

/**
 * ADR-638: «Γίνε μέλος» right beside «Ακολούθησε» wherever a box or an
 * independent coach can be followed, so a newcomer sees the two are not the
 * same thing (ANR 2026-11-10). It is the louder of the two (Spark).
 *
 * It opens the box page with `?join=1`, which starts the one join flow
 * (ADR-552): the box's packages, its member join link, or «Ζήτα να γίνεις
 * μέλος». The box's members and staff see nothing; while their request
 * waits the person sees «Αίτημα εστάλη», which opens the same flow (the
 * «ask» sheet lets them withdraw it). Beside it «Ακολούθησε» is outlined
 * (`quiet`), so the two never look alike.
 */
export function JoinBoxButton({
  slug,
  status,
  wide = false,
}: {
  slug: string;
  /** Where the viewer stands with the box (API `my_join`); unknown reads as «may join». */
  status: BoxJoinStatus | null | undefined;
  wide?: boolean;
}) {
  const t = useTranslations("Social");
  if (!offersJoin(status)) return null;
  const waiting = status === "requested";
  return (
    <Link
      href={joinBoxHref(slug)}
      className={`flex min-h-11 items-center justify-center whitespace-nowrap rounded-2xl px-4 text-sm font-extrabold ${wide ? "w-full" : ""}`}
      style={waiting ? { background: "var(--panel-raised)", border: "1px solid var(--border)", color: "var(--text-soft)" } : SPARK_GO_STYLE}
      data-testid="join-box"
      data-join-status={status ?? "none"}
    >
      {waiting ? t("joinSent") : t("join")}
    </Link>
  );
}

/** The box page with its join flow started (`JoinBoxAction` reads `?join=1`). */
export function joinBoxHref(slug: string) {
  return `/b/${encodeURIComponent(slug)}?join=1`;
}

/**
 * Where the viewer already belongs (ANR 2026-11-13): a list row that shows a
 * box without «Γίνε μέλος» says why, «Μέλος box» or «Staff», so the list and
 * the box page never seem to disagree. Nothing for anyone else.
 */
export function BoxRelationChip({ status, kind }: { status: BoxJoinStatus | null | undefined; kind: string | null | undefined }) {
  const t = useTranslations("Social");
  if (status !== "member" && status !== "staff") return null;
  const providerKind = kind === "coach" ? "coach" : "box";
  return (
    <span
      className="inline-flex shrink-0 items-center rounded-full px-2 py-0.5 text-[11px] font-bold"
      style={{ background: "var(--panel-raised)", color: "var(--text-soft)", border: "1px solid var(--border)" }}
      data-testid="box-relation"
      data-relation={status}
    >
      {status === "staff" ? t("relationBoxStaff", { kind: providerKind }) : t("relationBoxMember", { kind: providerKind })}
    </span>
  );
}

/** Whether «Γίνε μέλος» shows: not to the box's members and staff. */
export function offersJoin(status: BoxJoinStatus | null | undefined) {
  return status !== "member" && status !== "staff";
}
