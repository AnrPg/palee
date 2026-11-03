"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useLocale, useTranslations } from "next-intl";
import { useId, useState } from "react";

import { createProgramme, fetchStaffProgrammes, STAFF_PROGRAMMES_KEY, type StaffProgramme } from "@/api/programmes";
import { PageHeader } from "@/components/PageHeader";
import { useSession } from "@/components/session-provider";
import { Pill, inputClass, inputStyle, primaryButtonClass, primaryButtonStyle } from "@/components/staff/staff-ui";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { adminHref, useOrganizationSlug } from "@/lib/organization-slug";

import { programmeMoney, ratingLabel, useProgrammeError } from "@/components/programmes/programme-ui";

/**
 * Προγραμματισμός › Προγράμματα προπόνησης (ADR-370, mockup W8 s1): the
 * programmes the box sells, with their state, buyers and rating. «Νέο
 * πρόγραμμα» asks only for a title and opens the weeks grid.
 */
export function ProgrammesConsole() {
  const t = useTranslations("Programmes");
  const locale = useLocale();
  const token = useSession().tokens?.access_token ?? "";
  const slug = useOrganizationSlug();
  const [creating, setCreating] = useState(false);

  const programmes = useQuery({
    queryKey: STAFF_PROGRAMMES_KEY,
    enabled: Boolean(token),
    queryFn: () => fetchStaffProgrammes(token),
  });
  const list = programmes.data ?? [];

  return (
    <div className="mx-auto flex w-full max-w-5xl flex-col gap-4 px-4 py-6" data-testid="programmes-console">
      <PageHeader
        title={t("title")}
        actions={
          <button type="button" className={primaryButtonClass} style={primaryButtonStyle} onClick={() => setCreating(true)} data-testid="programme-new">
            {t("new")}
          </button>
        }
      />
      <p className="text-sm" style={{ color: "var(--muted)" }}>{t("staffHint")}</p>

      <div className="overflow-hidden rounded-[2rem]" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
        {programmes.isLoading ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : programmes.isError ? (
          <div className="p-4"><ErrorNotice>{t("loadFailed")}</ErrorNotice></div>
        ) : list.length === 0 ? (
          <p className="px-6 py-8 text-sm" style={{ color: "var(--dim)" }}>{t("empty")}</p>
        ) : (
          <ul>
            {list.map((programme, index) => (
              <li key={programme.id} style={{ borderTop: index === 0 ? "none" : "1px solid var(--border)" }}>
                <ProgrammeRow programme={programme} locale={locale} href={adminHref(`/admin/programmes/${programme.id}`, slug)} />
              </li>
            ))}
          </ul>
        )}
      </div>

      {creating ? <NewProgrammeDialog token={token} slug={slug} onClose={() => setCreating(false)} /> : null}
    </div>
  );
}

export function StatusPill({ status }: { status: StaffProgramme["status"] }) {
  const t = useTranslations("Programmes");
  const tone = status === "published" ? "success" : status === "archived" ? "neutral" : "warning";
  return <Pill tone={tone}>{t(`status.${status}`)}</Pill>;
}

function ProgrammeRow({ programme, locale, href }: { programme: StaffProgramme; locale: string; href: string }) {
  const t = useTranslations("Programmes");
  const weeks = programme.version?.weeks ?? programme.draft_weeks;
  const rating = ratingLabel(locale, programme.reviews?.average, programme.reviews?.count);
  return (
    <Link href={href} className="flex w-full flex-wrap items-center gap-x-4 gap-y-1 px-6 py-4" data-testid={`programme-row-${programme.id}`}>
      <span className="min-w-0 flex-1">
        <span className="block truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{programme.title}</span>
        <span className="block text-xs" style={{ color: "var(--muted)" }}>
          {[t("weeks", { count: weeks }), programme.price_cents ? programmeMoney(locale, programme.price_cents, programme.currency) : null, rating]
            .filter(Boolean)
            .join(" · ")}
        </span>
      </span>
      {programme.sales?.buyers ? (
        <span className="text-xs" style={{ color: "var(--text-soft)" }}>{t("buyers", { count: programme.sales.buyers })}</span>
      ) : null}
      <StatusPill status={programme.status} />
    </Link>
  );
}

function NewProgrammeDialog({ token, slug, onClose }: { token: string; slug: string | null; onClose: () => void }) {
  const t = useTranslations("Programmes");
  const router = useRouter();
  const queryClient = useQueryClient();
  const programmeError = useProgrammeError();
  const titleId = useId();
  const [title, setTitle] = useState("");
  const [touched, setTouched] = useState(false);
  const invalid = title.trim().length < 2;

  const create = useMutation({
    mutationFn: () => createProgramme(token, { title: title.trim(), draft_weeks: 4 }),
    onSuccess: async (programme) => {
      await queryClient.invalidateQueries({ queryKey: STAFF_PROGRAMMES_KEY });
      router.push(adminHref(`/admin/programmes/${programme.id}`, slug));
    },
  });

  return (
    <Dialog
      onClose={onClose}
      title={t("new")}
      size="sm"
      testId="programme-new-dialog"
      onSubmit={() => {
        setTouched(true);
        if (!invalid) create.mutate();
      }}
      footer={
        <>
          <button type="button" onClick={onClose} className="min-h-11 px-3 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("cancel")}
          </button>
          <button type="submit" disabled={create.isPending} className={primaryButtonClass} style={primaryButtonStyle} data-testid="programme-create">
            {t("create")}
          </button>
        </>
      }
    >
      <label htmlFor={titleId} className="mb-1 block text-sm font-semibold" style={{ color: "var(--text)" }}>{t("fieldTitle")}</label>
      <input
        id={titleId}
        className={inputClass}
        style={touched && invalid ? { ...inputStyle, borderColor: "var(--danger)" } : inputStyle}
        value={title}
        maxLength={120}
        aria-invalid={touched && invalid}
        onChange={(event) => setTitle(event.target.value)}
        placeholder={t("titlePlaceholder")}
        data-testid="programme-title-input"
      />
      {touched && invalid ? <p className="mt-1 text-xs" style={{ color: "var(--danger)" }}>{t("titleRequired")}</p> : null}
      {create.isError ? <ErrorNotice variant="field" className="mt-2">{programmeError(create.error)}</ErrorNotice> : null}
    </Dialog>
  );
}
