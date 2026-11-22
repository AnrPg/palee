"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { fetchFinanceCleanupRecords, purgeFinanceRecord, type FinanceCleanupRecord } from "@/api/finance";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";
import { PasswordInput } from "@/components/ui/PasswordInput";

// Finance cleanup: soft-delete a wrong invoice, receipt or payment after the
// signed-in user re-enters their password. One component, shown both in
// Settings → Finance and in Finance → Accounting.

export function FinanceCleanupSection({ token }: { token: string }) {
  const locale = useUiLocale();
  const i18n = useUiTranslations();
  const tAuth = useTranslations("authRecovery");
  const queryClient = useQueryClient();
  const [open, setOpen] = useState(false);
  const [search, setSearch] = useState("");
  const [selected, setSelected] = useState<FinanceCleanupRecord | null>(null);
  const [password, setPassword] = useState("");
  const [reason, setReason] = useState("");

  const recordsQuery = useQuery({
    queryKey: ["admin", "finance", "cleanup-records", search],
    queryFn: () => fetchFinanceCleanupRecords(token, { q: search, limit: "50" }),
    enabled: open,
  });

  const purgeMutation = useMutation({
    mutationFn: () => {
      if (!selected) throw new Error("finance_cleanup_record_missing");

      return purgeFinanceRecord(token, selected.id, {
        record_type: selected.record_type,
        password,
        reason: reason.trim() || i18n("featureFinanceCleanupDefaultReason"),
      });
    },
    onSuccess: () => {
      setSelected(null);
      setPassword("");
      setReason("");
      void queryClient.invalidateQueries({ queryKey: ["admin", "finance"] });
      void queryClient.invalidateQueries({ queryKey: ["admin", "finance", "cleanup-records"] });
    },
  });

  const records = recordsQuery.data?.records ?? [];
  const canPurge = Boolean(selected && password.trim() && !purgeMutation.isPending);
  const errorMessage = purgeMutation.error instanceof Error ? localizeError(purgeMutation.error, i18n) : null;

  return (
    <div
      className="rounded-[1.4rem] border p-4"
      style={{ background: "var(--panel-muted)", borderColor: "var(--border)" }}
    >
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
            {i18n("featureFinanceCleanupTitle")}
          </p>
          <p className="mt-1 text-xs leading-5" style={{ color: "var(--dim)" }}>
            {i18n("featureFinanceCleanupDescription")}
          </p>
        </div>
        <button
          className="rounded-full px-4 py-2 text-sm font-semibold"
          style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
          type="button"
          onClick={() => setOpen(true)}
        >
          {i18n("featureFinanceCleanupOpen")}
        </button>
      </div>

      {open ? (
        <Dialog
          onClose={() => setOpen(false)}
          title={i18n("featureFinanceCleanupModalTitle")}
          description={<span className="block max-w-2xl text-xs leading-5" style={{ color: "var(--dim)" }}>{i18n("featureFinanceCleanupModalDescription")}</span>}
          closeLabel={i18n("featureFinanceCleanupClose")}
          size="5xl"
          variant="center"
        >
            <div className="grid gap-4 lg:grid-cols-[1.35fr_0.85fr]">
              <div className="space-y-3">
                <input
                  className="w-full rounded-2xl border px-4 py-3 text-sm outline-none"
                  placeholder={i18n("featureFinanceCleanupSearchPlaceholder")}
                  style={{ background: "var(--panel-muted)", borderColor: "var(--border)", color: "var(--text)" }}
                  value={search}
                  onChange={(event) => setSearch(event.target.value)}
                />
                <div className="space-y-2">
                  {recordsQuery.isLoading ? (
                    <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("loading33ce417")}</p>
                  ) : records.length === 0 ? (
                    <p className="text-sm" style={{ color: "var(--dim)" }}>{i18n("featureFinanceCleanupEmpty")}</p>
                  ) : (
                    records.map((record) => {
                      const active = selected?.id === record.id;
                      return (
                        <button
                          key={`${record.record_type}-${record.id}`}
                          className="w-full rounded-2xl border p-4 text-start transition-colors"
                          style={{
                            background: active
                              ? "color-mix(in srgb, var(--danger) 10%, var(--panel-muted))"
                              : "var(--panel-muted)",
                            borderColor: active ? "var(--danger)" : "var(--border)",
                          }}
                          type="button"
                          onClick={() => {
                            setSelected(record);
                            purgeMutation.reset();
                          }}
                        >
                          <span className="flex flex-wrap items-center justify-between gap-3">
                            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                              {record.code || record.label}
                            </span>
                            <span className="rounded-full px-2.5 py-1 text-[0.68rem] font-semibold uppercase tracking-[0.16em]" style={{ background: "var(--bg)", color: "var(--dim)" }}>
                              {record.record_type}
                            </span>
                          </span>
                          <span className="mt-2 block text-xs leading-5" style={{ color: "var(--dim)" }}>
                            {formatCleanupAmount(record, locale)} · {record.status ?? i18n("featureFinanceCleanupUnknown")} · {record.issued_on ?? record.paid_on ?? record.inserted_at ?? ""}
                          </span>
                        </button>
                      );
                    })
                  )}
                </div>
              </div>

              <div className="space-y-4 rounded-2xl border p-4" style={{ background: "var(--panel-muted)", borderColor: "var(--border)" }}>
                <div>
                  <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                    {selected ? selected.code || selected.label : i18n("featureFinanceCleanupNoSelection")}
                  </p>
                  <p className="mt-1 text-xs leading-5" style={{ color: "var(--dim)" }}>
                    {i18n("featureFinanceCleanupImpact")}
                  </p>
                </div>
                <label className="block space-y-2">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                    {i18n("featureFinanceCleanupReason")}
                  </span>
                  <textarea
                    className="min-h-24 w-full rounded-2xl border px-4 py-3 text-sm outline-none"
                    style={{ background: "var(--bg)", borderColor: "var(--border)", color: "var(--text)" }}
                    value={reason}
                    onChange={(event) => setReason(event.target.value)}
                  />
                </label>
                <label className="block space-y-2">
                  <span className="text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--dim)" }}>
                    {i18n("featureFinanceCleanupPassword")}
                  </span>
                  <PasswordInput
                    className="w-full rounded-2xl border px-4 py-3 text-sm outline-none"
                    style={{ background: "var(--bg)", borderColor: "var(--border)", color: "var(--text)" }}
                    autoComplete="current-password"
                    value={password}
                    onChange={(event) => setPassword(event.target.value)}
                  />
                  {/* It's the signed-in owner's own login password (same gate as
                      account deletion / email change), not a separate code. The
                      reset opens in a new tab so this dialog is not lost. */}
                  <a
                    href="/forgot-password"
                    target="_blank"
                    rel="noopener noreferrer"
                    className="inline-block text-xs font-semibold hover:opacity-80"
                    style={{ color: "var(--primary)" }}
                  >
                    {tAuth("forgotPasswordLink")}
                  </a>
                </label>
                {errorMessage ? <ErrorNotice>{errorMessage}</ErrorNotice> : null}
                {purgeMutation.isSuccess ? (
                  <p className="text-sm" style={{ color: "var(--success)" }}>{i18n("featureFinanceCleanupSuccess")}</p>
                ) : null}
                <button
                  className="w-full rounded-full px-4 py-3 text-sm font-semibold disabled:opacity-50"
                  disabled={!canPurge}
                  style={{ background: "var(--danger)", color: "var(--danger-contrast)" }}
                  type="button"
                  onClick={() => purgeMutation.mutate()}
                >
                  {purgeMutation.isPending ? i18n("featureFinanceCleanupPending") : i18n("featureFinanceCleanupSubmit")}
                </button>
              </div>
            </div>
        </Dialog>
      ) : null}
    </div>
  );
}

function formatCleanupAmount(record: FinanceCleanupRecord, locale: string) {
  const cents = typeof record.amount_cents === "number" ? record.amount_cents : 0;
  const currency = record.currency || "EUR";
  return new Intl.NumberFormat(locale, { style: "currency", currency }).format(cents / 100);
}
