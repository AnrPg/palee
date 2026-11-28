"use client";

import { useInfiniteQuery, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import Link from "next/link";
import { useTranslations } from "next-intl";
import { useEffect, useState, type ReactNode } from "react";

import {
  fetchFinanceCleanupPackages,
  fetchFinanceCleanupRecord,
  fetchFinanceCleanupRecords,
  purgeFinanceRecord,
  type FinanceCleanupLinkedRecord,
  type FinanceCleanupRecord,
  type FinanceCleanupRecordDetails,
  type FinanceCleanupRecordType,
} from "@/api/finance";
import { UserSearchField } from "@/components/admin/finance/shared/UserSearchField";
import { CollapsibleFilterBar } from "@/components/filters/CollapsibleFilterBar";
import { DateInput } from "@/components/ui/DateInput";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { PasswordInput } from "@/components/ui/PasswordInput";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import {
  activeCleanupFilterCount,
  cleanupQuery,
  CLEANUP_KINDS,
  CLEANUP_QUICK_RANGES,
  EMPTY_CLEANUP_FILTERS,
  matchingQuickRange,
  quickRange,
  type CleanupFilters,
} from "@/lib/finance-cleanup";
import { adminHref, useOrganizationSlug, useOrganizationTimeZone } from "@/lib/organization-slug";
import { dateKeyInZone } from "@/lib/zoned-time";

// Finance cleanup (ADR-797): find a wrong invoice, receipt or payment with a
// search and filters, open its details in a side panel and soft-delete it
// there after the signed-in user re-enters their password. One component,
// shown both in Settings → Finance and in Finance → Accounting.

const PAGE_SIZE = 30;
const SEARCH_DEBOUNCE_MS = 300;

type Selection = { id: string; record_type: FinanceCleanupRecordType };

const fieldClass = "min-h-11 w-full rounded-xl px-3 py-2 text-sm";
const fieldStyle = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };

export function FinanceCleanupSection({ token }: { token: string }) {
  const t = useTranslations("FinanceCleanup");
  const [open, setOpen] = useState(false);

  return (
    <div className="rounded-[1.4rem] border p-4" style={{ background: "var(--panel-muted)", borderColor: "var(--border)" }}>
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("title")}
          </p>
          <p className="mt-1 text-xs leading-5" style={{ color: "var(--dim)" }}>
            {t("description")}
          </p>
        </div>
        <button
          className="rounded-full px-4 py-2 text-sm font-semibold"
          style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
          type="button"
          onClick={() => setOpen(true)}
        >
          {t("open")}
        </button>
      </div>

      {open ? <CleanupDialog token={token} onClose={() => setOpen(false)} /> : null}
    </div>
  );
}

function CleanupDialog({ token, onClose }: { token: string; onClose: () => void }) {
  const t = useTranslations("FinanceCleanup");
  const locale = useUiLocale();
  const zone = useOrganizationTimeZone();
  const today = dateKeyInZone(new Date(), zone);
  const [filters, setFilters] = useState<CleanupFilters>(EMPTY_CLEANUP_FILTERS);
  const [searchText, setSearchText] = useState("");
  const [selected, setSelected] = useState<Selection | null>(null);
  const [purged, setPurged] = useState(false);

  // The search runs once typing pauses, not on every key.
  useEffect(() => {
    const timer = setTimeout(() => setFilters((current) => (current.q === searchText ? current : { ...current, q: searchText })), SEARCH_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [searchText]);

  const update = (patch: Partial<CleanupFilters>) => setFilters((current) => ({ ...current, ...patch }));

  const recordsQuery = useInfiniteQuery({
    queryKey: ["admin", "finance", "cleanup-records", filters],
    initialPageParam: null as string | null,
    queryFn: ({ pageParam }) => fetchFinanceCleanupRecords(token, cleanupQuery(filters, { cursor: pageParam, limit: PAGE_SIZE })),
    getNextPageParam: (lastPage) => lastPage.next_cursor ?? null,
  });

  const packagesQuery = useQuery({
    queryKey: ["admin", "finance", "cleanup-packages"],
    queryFn: () => fetchFinanceCleanupPackages(token),
  });

  const records = recordsQuery.data?.pages.flatMap((page) => page.records) ?? [];
  const packages = packagesQuery.data?.packages ?? [];
  const activeQuick = matchingQuickRange(filters, today);

  return (
    <Dialog
      onClose={onClose}
      title={t("modalTitle")}
      description={<span className="block max-w-2xl text-xs leading-5" style={{ color: "var(--dim)" }}>{t("modalDescription")}</span>}
      closeLabel={t("close")}
      size="5xl"
      variant="center"
    >
      <div className="space-y-4">
        <CollapsibleFilterBar
          ariaLabel={t("filtersAria")}
          search={{
            value: searchText,
            onChange: (value) => {
              setSearchText(value);
              setPurged(false);
            },
            placeholder: t("searchPlaceholder"),
            ariaLabel: t("searchAria"),
            maxLength: 120,
          }}
          activeCount={activeCleanupFilterCount(filters)}
          onClear={() => setFilters({ ...EMPTY_CLEANUP_FILTERS, q: filters.q })}
        >
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <UserSearchField
              label={t("customer")}
              token={token}
              value={filters.userId}
              onChange={(userId) => update({ userId })}
            />
            <FilterField label={t("from")}>
              <DateInput className={fieldClass} style={fieldStyle} value={filters.from} max={filters.to || undefined} onValueChange={(from) => update({ from })} />
            </FilterField>
            <FilterField label={t("to")}>
              <DateInput className={fieldClass} style={fieldStyle} value={filters.to} min={filters.from || undefined} onValueChange={(to) => update({ to })} />
            </FilterField>
            <FilterField label={t("package")}>
              <Select className={fieldClass} style={fieldStyle} value={filters.packageId} onValueChange={(packageId) => update({ packageId })}>
                <option value="">{t("all")}</option>
                {packages.map((pkg) => (
                  <option key={pkg.id} value={pkg.id}>
                    {pkg.active ? pkg.name : t("packageInactive", { name: pkg.name })}
                  </option>
                ))}
              </Select>
            </FilterField>
            <FilterField label={t("kind")}>
              <Select
                className={fieldClass}
                style={fieldStyle}
                value={filters.kind}
                onValueChange={(kind) => update({ kind: kind as CleanupFilters["kind"] })}
              >
                <option value="">{t("all")}</option>
                {CLEANUP_KINDS.map((kind) => (
                  <option key={kind} value={kind}>
                    {t(`kinds.${kind}`)}
                  </option>
                ))}
              </Select>
            </FilterField>
          </div>
          <div className="flex flex-wrap gap-2">
            {CLEANUP_QUICK_RANGES.map((range) => {
              const on = activeQuick === range;
              return (
                <button
                  key={range}
                  type="button"
                  aria-pressed={on}
                  onClick={() => update(on ? { from: "", to: "" } : quickRange(range, today))}
                  className="min-h-9 rounded-full px-3 text-xs font-semibold"
                  style={
                    on
                      ? { background: "color-mix(in srgb, var(--primary) 14%, var(--panel))", border: "1px solid var(--primary)", color: "var(--text)" }
                      : { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text-soft)" }
                  }
                >
                  {t(`quick.${range}`)}
                </button>
              );
            })}
          </div>
        </CollapsibleFilterBar>

        {purged ? (
          <p className="text-sm" role="status" style={{ color: "var(--success)" }}>
            {t("success")}
          </p>
        ) : null}

        {recordsQuery.isPending ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
        ) : recordsQuery.isError ? (
          <ErrorNotice>{t("loadFailed")}</ErrorNotice>
        ) : records.length === 0 ? (
          <p className="text-sm" style={{ color: "var(--dim)" }}>{t("empty")}</p>
        ) : (
          <div className="space-y-2">
            <p className="text-xs" style={{ color: "var(--dim)" }}>{t("shown", { count: records.length })}</p>
            <ul className="space-y-2">
              {records.map((record) => (
                <li key={`${record.record_type}-${record.id}`}>
                  <RecordRow
                    record={record}
                    locale={locale}
                    active={selected?.id === record.id}
                    onOpen={() => setSelected({ id: record.id, record_type: record.record_type })}
                  />
                </li>
              ))}
            </ul>
            {recordsQuery.hasNextPage ? (
              <div className="flex justify-center pt-1">
                <button
                  type="button"
                  disabled={recordsQuery.isFetchingNextPage}
                  onClick={() => void recordsQuery.fetchNextPage()}
                  className="min-h-10 rounded-full px-5 text-sm font-semibold disabled:opacity-50"
                  style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
                >
                  {recordsQuery.isFetchingNextPage ? t("loading") : t("more")}
                </button>
              </div>
            ) : null}
          </div>
        )}
      </div>

      {selected ? (
        <RecordPanel
          key={`${selected.record_type}-${selected.id}`}
          token={token}
          selection={selected}
          onOpen={setSelected}
          onClose={() => setSelected(null)}
          onPurged={() => {
            setSelected(null);
            setPurged(true);
          }}
        />
      ) : null}
    </Dialog>
  );
}

function FilterField({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="block space-y-1">
      <span className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
        {label}
      </span>
      {children}
    </label>
  );
}

function RecordRow({ record, locale, active, onOpen }: { record: FinanceCleanupRecord; locale: string; active: boolean; onOpen: () => void }) {
  const t = useTranslations("FinanceCleanup");
  const name = record.customer_name || t("noCustomer");
  const amount = formatAmount(record.amount_cents, record.currency, locale);

  return (
    <button
      type="button"
      onClick={onOpen}
      aria-label={t("openRecord", { kind: t(`kinds.${record.record_type}`), amount, name })}
      className="grid w-full grid-cols-[minmax(0,1fr)_auto] gap-x-3 gap-y-1 rounded-2xl border p-3 text-start transition-colors sm:p-4"
      style={{
        background: active ? "color-mix(in srgb, var(--primary) 8%, var(--panel-muted))" : "var(--panel-muted)",
        borderColor: active ? "var(--primary)" : "var(--border)",
      }}
    >
      <span className="truncate text-sm font-semibold" style={{ color: "var(--text)" }}>{name}</span>
      <span className="text-end text-sm font-bold tabular-nums" style={{ color: "var(--text)" }}>{amount}</span>
      <span className="flex min-w-0 flex-wrap items-center gap-1.5 text-xs" style={{ color: "var(--dim)" }}>
        <Tag>{t(`kinds.${record.record_type}`)}</Tag>
        <Tag tone={statusTone(record.status)}>{statusLabel(t, record.record_type, record.status)}</Tag>
        {record.package_name ? <span className="truncate">{record.package_name}</span> : null}
        {record.code ? <span className="truncate">· {record.code}</span> : null}
      </span>
      <span className="text-end text-xs tabular-nums" style={{ color: "var(--dim)" }}>{formatDay(record.occurred_on, locale)}</span>
    </button>
  );
}

function Tag({ children, tone = "neutral" }: { children: ReactNode; tone?: "neutral" | "ok" | "warn" | "bad" }) {
  const color = tone === "ok" ? "var(--success)" : tone === "warn" ? "var(--warning)" : tone === "bad" ? "var(--danger)" : "var(--text-soft)";
  return (
    <span
      className="rounded-full px-2 py-0.5 text-[0.7rem] font-semibold"
      style={{ background: tone === "neutral" ? "var(--bg)" : `color-mix(in srgb, ${color} 14%, var(--panel))`, color }}
    >
      {children}
    </span>
  );
}

function RecordPanel({
  token,
  selection,
  onOpen,
  onClose,
  onPurged,
}: {
  token: string;
  selection: Selection;
  onOpen: (selection: Selection) => void;
  onClose: () => void;
  onPurged: () => void;
}) {
  const t = useTranslations("FinanceCleanup");
  const locale = useUiLocale();
  const slug = useOrganizationSlug();

  const detailsQuery = useQuery({
    queryKey: ["admin", "finance", "cleanup-record", selection.record_type, selection.id],
    queryFn: () => fetchFinanceCleanupRecord(token, selection.record_type, selection.id),
  });
  const record = detailsQuery.data?.record;

  return (
    <Dialog
      onClose={onClose}
      variant="drawer"
      layer="modal"
      size="full"
      panelClassName="md:max-w-[480px]"
      panelStyle={{ background: "var(--bg)" }}
      closeLabel={t("close")}
      eyebrow={<span style={{ color: "var(--dim)" }}>{t(`kinds.${selection.record_type}`)}</span>}
      title={record ? `${formatAmount(record.amount_cents, record.currency, locale)} · ${record.customer_name || t("noCustomer")}` : t(`kinds.${selection.record_type}`)}
      description={record ? formatDay(record.occurred_on, locale) : undefined}
      bodyClassName="space-y-4 pt-1"
    >
      {detailsQuery.isPending ? (
        <p className="text-sm" style={{ color: "var(--dim)" }}>{t("loading")}</p>
      ) : !record ? (
        <ErrorNotice>{t("detailsLoadFailed")}</ErrorNotice>
      ) : (
        <>
          {record.user_id ? (
            <Card title={t("customer")}>
              <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>{record.customer_name || t("noCustomer")}</p>
              {record.customer_email ? <p className="break-all text-xs" style={{ color: "var(--dim)" }}>{record.customer_email}</p> : null}
              <Link
                href={adminHref(`/admin/finance?tab=members&member=${encodeURIComponent(record.user_id)}`, slug)}
                className="inline-block text-sm font-semibold hover:opacity-80"
                style={{ color: "var(--primary)" }}
              >
                {t("openMember")} ›
              </Link>
            </Card>
          ) : null}

          <RecordFacts record={record} locale={locale} />

          {record.lines.length > 0 ? <RecordLines record={record} locale={locale} /> : null}

          {record.linked.length > 0 ? (
            <Card title={t("linked")}>
              <ul className="space-y-1">
                {record.linked.map((linked) => (
                  <li key={`${linked.record_type}-${linked.id}`}>
                    <LinkedButton linked={linked} locale={locale} onOpen={onOpen} />
                  </li>
                ))}
              </ul>
            </Card>
          ) : null}

          <PurgeBox token={token} record={record} onPurged={onPurged} />
        </>
      )}
    </Dialog>
  );
}

function Card({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="space-y-1.5 rounded-2xl border p-3" style={{ background: "var(--panel)", borderColor: "var(--border)" }}>
      <h3 className="text-[0.7rem] font-semibold uppercase tracking-[0.16em]" style={{ color: "var(--dim)" }}>{title}</h3>
      {children}
    </section>
  );
}

function RecordFacts({ record, locale }: { record: FinanceCleanupRecordDetails; locale: string }) {
  const t = useTranslations("FinanceCleanup");
  const period =
    record.service_period_start && record.service_period_end
      ? t("period", { start: formatDay(record.service_period_start, locale), end: formatDay(record.service_period_end, locale) })
      : null;
  const isDocument = record.record_type !== "payment";

  const facts: Array<[string, ReactNode]> = [
    [t("fields.status"), statusLabel(t, record.record_type, record.status)],
    ...(record.code ? [[t("fields.number"), record.code] as [string, ReactNode]] : []),
    ...(record.package_name ? [[t("fields.package"), record.package_name] as [string, ReactNode]] : []),
    ...(record.issued_on ? [[t("fields.issued"), formatDay(record.issued_on, locale)] as [string, ReactNode]] : []),
    ...(record.due_on ? [[t("fields.due"), formatDay(record.due_on, locale)] as [string, ReactNode]] : []),
    ...(record.paid_on ? [[t("fields.paidOn"), formatDay(record.paid_on, locale)] as [string, ReactNode]] : []),
    ...(period ? [[t("fields.period"), period] as [string, ReactNode]] : []),
    ...(record.payment_method ? [[t("fields.method"), methodLabel(t, record.payment_method)] as [string, ReactNode]] : []),
    ...(isDocument && typeof record.balance_due_cents === "number"
      ? [[t("fields.balance"), formatAmount(record.balance_due_cents, record.currency, locale)] as [string, ReactNode]]
      : []),
    ...(record.reversed_cents ? [[t("fields.reversed"), formatAmount(record.reversed_cents, record.currency, locale)] as [string, ReactNode]] : []),
    ...(record.created_by_name ? [[t("fields.recordedBy"), record.created_by_name] as [string, ReactNode]] : []),
    ...(record.fiscal_receipt_ref ? [[t("fields.fiscal"), record.fiscal_receipt_ref] as [string, ReactNode]] : []),
    ...(record.notes ? [[t("fields.notes"), record.notes] as [string, ReactNode]] : []),
  ];

  return (
    <dl className="grid grid-cols-[auto_minmax(0,1fr)] gap-x-4 gap-y-1.5 px-1 text-sm">
      {facts.map(([label, value]) => (
        <div key={label} className="contents">
          <dt style={{ color: "var(--dim)" }}>{label}</dt>
          <dd className="break-words font-semibold" style={{ color: "var(--text)" }}>{value}</dd>
        </div>
      ))}
    </dl>
  );
}

function RecordLines({ record, locale }: { record: FinanceCleanupRecordDetails; locale: string }) {
  const t = useTranslations("FinanceCleanup");
  const money = (cents: number | null | undefined) => formatAmount(cents, record.currency, locale);

  return (
    <Card title={t("lines")}>
      <ul className="space-y-1 text-sm">
        {record.lines.map((line) => (
          <li key={line.id} className="flex items-start justify-between gap-3">
            <span className="min-w-0" style={{ color: "var(--text-soft)" }}>
              {line.description}
              {(line.quantity ?? 1) > 1 ? (
                <span className="block text-xs" style={{ color: "var(--dim)" }}>
                  {t("lineQty", { count: line.quantity ?? 1, price: money(line.unit_amount_cents) })}
                </span>
              ) : null}
            </span>
            <span className="font-semibold tabular-nums" style={{ color: "var(--text)" }}>{money(line.total_cents)}</span>
          </li>
        ))}
      </ul>
      <div className="space-y-1 border-t pt-2 text-sm" style={{ borderColor: "var(--border)" }}>
        {record.discount_cents ? (
          <>
            <Total label={t("subtotal")} value={money(record.subtotal_cents)} />
            <Total label={t("discount")} value={`−${money(record.discount_cents)}`} />
          </>
        ) : null}
        <Total label={t("total")} value={money(record.amount_cents)} strong />
      </div>
    </Card>
  );
}

function Total({ label, value, strong = false }: { label: string; value: string; strong?: boolean }) {
  return (
    <div className="flex justify-between gap-3">
      <span style={{ color: strong ? "var(--text)" : "var(--text-soft)", fontWeight: strong ? 700 : 400 }}>{label}</span>
      <span className="tabular-nums" style={{ color: "var(--text)", fontWeight: strong ? 700 : 600 }}>{value}</span>
    </div>
  );
}

function LinkedButton({ linked, locale, onOpen }: { linked: FinanceCleanupLinkedRecord; locale: string; onOpen: (selection: Selection) => void }) {
  const t = useTranslations("FinanceCleanup");
  const kind = t(`kinds.${linked.record_type}`);
  const amount = formatAmount(linked.amount_cents, linked.currency, locale);

  return (
    <button
      type="button"
      onClick={() => onOpen({ id: linked.id, record_type: linked.record_type })}
      aria-label={t("linkedOpen", { kind, amount })}
      className="flex w-full items-center justify-between gap-3 rounded-xl px-2 py-1.5 text-start text-sm hover:opacity-80"
      style={{ color: "var(--primary)" }}
    >
      <span className="min-w-0 truncate font-semibold">
        {kind}
        {linked.code ? ` ${linked.code}` : ""} · {amount}
      </span>
      <span className="shrink-0 text-xs" style={{ color: "var(--dim)" }}>
        {formatDay(linked.occurred_on, locale)} ›
      </span>
    </button>
  );
}

function PurgeBox({ token, record, onPurged }: { token: string; record: FinanceCleanupRecordDetails; onPurged: () => void }) {
  const t = useTranslations("FinanceCleanup");
  const tAuth = useTranslations("authRecovery");
  const i18n = useUiTranslations();
  const queryClient = useQueryClient();
  const [expanded, setExpanded] = useState(false);
  const [password, setPassword] = useState("");
  const [reason, setReason] = useState("");

  const purgeMutation = useMutation({
    mutationFn: () =>
      purgeFinanceRecord(token, record.id, {
        record_type: record.record_type,
        password,
        reason: reason.trim() || t("defaultReason"),
      }),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["admin", "finance"] });
      onPurged();
    },
  });

  const errorMessage = purgeMutation.error instanceof Error ? localizeError(purgeMutation.error, i18n) : null;
  const canPurge = Boolean(password.trim()) && !purgeMutation.isPending;

  return (
    <section
      className="space-y-3 rounded-2xl border p-3"
      style={{ background: "color-mix(in srgb, var(--danger) 6%, var(--panel))", borderColor: "color-mix(in srgb, var(--danger) 40%, var(--border))" }}
    >
      <div>
        <h3 className="text-sm font-semibold" style={{ color: "var(--danger)" }}>{t("cleanup")}</h3>
        <p className="mt-1 text-xs leading-5" style={{ color: "var(--dim)" }}>{t("impact")}</p>
      </div>
      {!expanded ? (
        <button
          type="button"
          onClick={() => setExpanded(true)}
          className="min-h-10 rounded-full border px-4 text-sm font-semibold"
          style={{ borderColor: "var(--danger)", color: "var(--danger)", background: "transparent" }}
        >
          {t("startCleanup")}
        </button>
      ) : (
        <form
          className="space-y-3"
          onSubmit={(event) => {
            event.preventDefault();
            if (canPurge) purgeMutation.mutate();
          }}
        >
          <label className="block space-y-1">
            <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("reason")}</span>
            <textarea
              className="min-h-20 w-full rounded-xl border px-3 py-2 text-sm outline-none"
              style={{ background: "var(--bg)", borderColor: "var(--border)", color: "var(--text)" }}
              value={reason}
              onChange={(event) => setReason(event.target.value)}
            />
          </label>
          <label className="block space-y-1">
            <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>{t("password")}</span>
            <PasswordInput
              className="w-full rounded-xl border px-3 py-2 text-sm outline-none"
              style={{ background: "var(--bg)", borderColor: "var(--border)", color: "var(--text)" }}
              autoComplete="current-password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
            />
          </label>
          {/* The signed-in user's own login password (the same gate as account
              deletion); the reset opens in a new tab so this panel is not lost. */}
          <a
            href="/forgot-password"
            target="_blank"
            rel="noopener noreferrer"
            className="inline-block text-xs font-semibold hover:opacity-80"
            style={{ color: "var(--primary)" }}
          >
            {tAuth("forgotPasswordLink")}
          </a>
          {errorMessage ? <ErrorNotice>{errorMessage}</ErrorNotice> : null}
          <button
            type="submit"
            disabled={!canPurge}
            className="min-h-11 w-full rounded-full px-4 text-sm font-semibold disabled:opacity-50"
            style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
          >
            {purgeMutation.isPending ? t("pending") : t("submit")}
          </button>
        </form>
      )}
    </section>
  );
}

type Translate = ReturnType<typeof useTranslations<"FinanceCleanup">>;

const DOCUMENT_STATUSES = new Set(["draft", "issued", "partially_paid", "paid", "overdue", "partially_refunded", "refunded", "void"]);
const PAYMENT_STATUSES = new Set(["paid", "pending", "refunded", "failed", "waived"]);
const METHODS = new Set(["cash", "bank_transfer", "card_manual", "card_terminal", "online", "other"]);

function statusLabel(t: Translate, recordType: FinanceCleanupRecordType, status: string | null | undefined): string {
  if (!status) return t("statusUnknown");
  if (recordType === "payment") {
    return PAYMENT_STATUSES.has(status) ? t(`paymentStatus.${status as "paid"}`) : t("statusUnknown");
  }
  return DOCUMENT_STATUSES.has(status) ? t(`documentStatus.${status as "paid"}`) : t("statusUnknown");
}

function methodLabel(t: Translate, method: string): string {
  return t(`method.${(METHODS.has(method) ? method : "other") as "other"}`);
}

function statusTone(status: string | null | undefined): "neutral" | "ok" | "warn" | "bad" {
  if (status === "paid") return "ok";
  if (status === "overdue" || status === "pending" || status === "partially_paid") return "warn";
  if (status === "failed" || status === "void") return "bad";
  return "neutral";
}

function formatAmount(cents: number | null | undefined, currency: string | null | undefined, locale: string) {
  return new Intl.NumberFormat(locale, { style: "currency", currency: currency || "EUR" }).format((cents ?? 0) / 100);
}

/** A calendar day (YYYY-MM-DD) as written, without shifting it through a time zone. */
function formatDay(day: string | null | undefined, locale: string) {
  if (!day) return "";
  const [year, month, date] = day.slice(0, 10).split("-").map(Number);
  if (!year || !month || !date) return day;
  return new Intl.DateTimeFormat(locale, { dateStyle: "medium", timeZone: "UTC" }).format(new Date(Date.UTC(year, month - 1, date)));
}
