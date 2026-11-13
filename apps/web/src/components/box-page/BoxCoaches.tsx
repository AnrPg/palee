"use client";

import Link from "next/link";
import { useState } from "react";
import { useTranslations } from "next-intl";

import type { PublicBoxPage } from "@/api/social";
import { useSession } from "@/components/session-provider";
import { PersonAvatar } from "@/components/social/PersonAvatar";
import { Dialog } from "@/components/ui/Dialog";

type Coach = PublicBoxPage["profile"]["coaches"][number];

/**
 * ADR-641: the box's coaches, each name in full (it wraps, never cut). A
 * signed-in viewer opens the coach's profile; a visitor without an account
 * (or on the box's own domain) gets a sheet with what the box shows and the
 * coach's «Λίγα λόγια» when their account is public.
 */
export function BoxCoaches({ coaches }: { coaches: Coach[] }) {
  const { status, tokens } = useSession();
  const signedIn = status === "authenticated" && Boolean(tokens?.access_token);
  const [open, setOpen] = useState<Coach | null>(null);

  return (
    <>
      <ul className="-mx-4 flex gap-3 overflow-x-auto px-4 pb-1 lg:mx-0 lg:grid lg:grid-cols-2 lg:px-0" data-testid="box-coaches">
        {coaches.map((coach) => {
          const body = <CoachCardBody coach={coach} />;
          const className = "flex h-full w-56 shrink-0 items-center gap-3 rounded-2xl p-3 text-start lg:w-auto";
          const style = { background: "var(--panel)", border: "1px solid var(--border)" };
          return (
            <li key={coach.id} className="flex">
              {signedIn ? (
                <Link href={`/people/${coach.id}`} className={className} style={style} data-testid="box-coach">
                  {body}
                </Link>
              ) : (
                <button type="button" onClick={() => setOpen(coach)} className={className} style={style} aria-haspopup="dialog" data-testid="box-coach">
                  {body}
                </button>
              )}
            </li>
          );
        })}
      </ul>
      {open ? <CoachSheet coach={open} onClose={() => setOpen(null)} /> : null}
    </>
  );
}

function CoachCardBody({ coach }: { coach: Coach }) {
  return (
    <>
      <PersonAvatar name={coach.nickname ?? "?"} url={coach.avatar_url} size={48} />
      <span className="flex min-w-0 flex-col">
        {/* ANR 2026-11-13: the whole name, wrapped. */}
        <span className="font-bold [overflow-wrap:anywhere]" style={{ color: "var(--text)" }} data-testid="box-coach-name">
          {coach.nickname ?? "?"}
        </span>
        {coach.class_types.length > 0 ? (
          <span className="line-clamp-2 text-xs" style={{ color: "var(--dim)" }}>{coach.class_types.join(" · ")}</span>
        ) : null}
      </span>
    </>
  );
}

function CoachSheet({ coach, onClose }: { coach: Coach; onClose: () => void }) {
  const t = useTranslations("BoxPage");
  const name = coach.nickname ?? "?";
  return (
    <Dialog onClose={onClose} ariaLabel={name} size="sm" variant="sheet" testId="box-coach-sheet">
      <div className="flex min-w-0 flex-col items-center gap-3 pb-2 text-center">
        <PersonAvatar name={name} url={coach.avatar_url} size={96} />
        <h2 className="text-xl font-extrabold [overflow-wrap:anywhere]" style={{ color: "var(--text)" }}>{name}</h2>
        {coach.class_types.length > 0 ? (
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>
            <span className="font-bold">{t("coachTeaches")}</span> {coach.class_types.join(" · ")}
          </p>
        ) : null}
        {coach.bio ? (
          <p className="whitespace-pre-line text-[15px] leading-relaxed" style={{ color: "var(--text)" }} data-testid="box-coach-bio">
            {coach.bio}
          </p>
        ) : null}
      </div>
    </Dialog>
  );
}
