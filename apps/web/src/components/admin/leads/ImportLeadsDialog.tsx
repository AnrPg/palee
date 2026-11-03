"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { importLeads, LEADS_KEY, type LeadImportResult } from "@/api/leads";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";

import { useLeadErrorText } from "./leads-ui";

/** The most rows one import takes (ADR-344). */
export const MAX_IMPORT_ROWS = 2000;

/**
 * «Εισαγωγή από αρχείο» (ADR-344): pick a CSV, see what would happen (a dry
 * run), then import. Repeated people are updated, never duplicated.
 */
export function ImportLeadsDialog({ onClose }: { onClose: () => void }) {
  const t = useTranslations("Leads");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const errorText = useLeadErrorText();
  const [csv, setCsv] = useState<string | null>(null);
  const [fileName, setFileName] = useState<string | null>(null);
  const [check, setCheck] = useState<LeadImportResult | null>(null);
  const [done, setDone] = useState<LeadImportResult | null>(null);

  const dryRun = useMutation({
    mutationFn: (text: string) => importLeads(token!, text, true),
    onSuccess: setCheck,
  });
  const run = useMutation({
    mutationFn: () => importLeads(token!, csv!, false),
    onSuccess: (result) => {
      setDone(result);
      void queryClient.invalidateQueries({ queryKey: LEADS_KEY });
    },
  });

  // A dry run counts rows that would be written as "valid".
  const ready = check ? check.rows.filter((row) => row.result !== "invalid").length : 0;
  const error = dryRun.isError ? errorText(dryRun.error) : run.isError ? errorText(run.error) : null;

  return (
    <Dialog
      onClose={onClose}
      title={t("importTitle")}
      size="md"
      dismissible={!run.isPending}
      error={error}
      testId="import-leads-dialog"
      footer={
        done ? (
          <DialogButton tone="primary" onClick={onClose}>
            {t("close")}
          </DialogButton>
        ) : (
          <>
            <DialogButton tone="ghost" onClick={onClose}>
              {t("cancel")}
            </DialogButton>
            <DialogButton tone="primary" disabled={!check || ready === 0 || run.isPending} onClick={() => run.mutate()} testId="import-leads-run">
              {t("importRun", { count: ready })}
            </DialogButton>
          </>
        )
      }
    >
      {done ? (
        <p className="text-sm" role="status" style={{ color: "var(--text)" }}>
          {t("importDone", { created: done.created, existing: done.existing, invalid: done.invalid })}
        </p>
      ) : (
        <div className="space-y-4">
          <label
            className="flex cursor-pointer flex-col items-center gap-2 rounded-[1.4rem] px-4 py-6 text-center"
            style={{ background: "var(--panel-muted)", border: "1px dashed var(--border-strong)" }}
          >
            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>
              {fileName ?? t("importPick")}
            </span>
            <span className="text-xs" style={{ color: "var(--muted)" }}>
              {t("importColumns", { max: MAX_IMPORT_ROWS })}
            </span>
            <input
              type="file"
              accept=".csv,text/csv"
              className="sr-only"
              data-testid="import-leads-file"
              onChange={async (event) => {
                const file = event.target.files?.[0];
                if (!file) return;
                const text = await file.text();
                setFileName(file.name);
                setCsv(text);
                setCheck(null);
                dryRun.mutate(text);
              }}
            />
          </label>
          {dryRun.isPending ? (
            <p className="text-sm" style={{ color: "var(--muted)" }}>
              {t("importChecking")}
            </p>
          ) : check ? (
            <div className="rounded-2xl p-3" style={{ background: "var(--panel-muted)" }} data-testid="import-leads-check">
              <p className="text-sm font-semibold" style={{ color: "var(--text)" }}>
                {t("importCheckTitle")}
              </p>
              <p className="text-sm" style={{ color: "var(--muted)" }}>
                {t("importCheck", { ready, invalid: check.invalid })}
              </p>
              {check.invalid > 0 ? (
                <p className="mt-1 text-xs" style={{ color: "var(--warning)" }}>
                  {t("importInvalidRows", {
                    rows: check.rows
                      .filter((row) => row.result === "invalid")
                      .slice(0, 10)
                      .map((row) => row.row)
                      .join(", "),
                  })}
                </p>
              ) : null}
            </div>
          ) : null}
        </div>
      )}
    </Dialog>
  );
}
