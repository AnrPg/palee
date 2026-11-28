"use client";

import { useRef, useState } from "react";

import {
  getInvoiceDownloadUrl,
  getInvoiceUploadUrl,
  issueFinanceInvoice,
  updateFinanceInvoice,
  voidFinanceInvoice,
  type FinanceRecord,
} from "@/api/finance";
import { SemanticLabel } from "@/components/semantic-label";
import { DateInput } from "@/components/ui/DateInput";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";
import { useUiLocale } from "@/i18n/use-ui-locale";

function field(record: FinanceRecord | null | undefined, key: string, fallback = "") {
  const value = record?.[key];
  if (value === null || value === undefined) return fallback;
  return String(value);
}

function money(uiLocale: string, cents: unknown) {
  const amount = typeof cents === "number" ? cents : Number(cents ?? 0);
  return new Intl.NumberFormat(uiLocale, { style: "currency", currency: "EUR" }).format(amount / 100);
}

function statusColor(status: string): string {
  if (["active", "paid", "applied"].includes(status)) return "var(--success)";
  if (["overdue", "void", "rejected"].includes(status)) return "var(--primary-strong)";
  if (["pending", "issued", "draft"].includes(status)) return "var(--primary)";
  return "var(--muted)";
}

/**
 * One charge opened in the movements list (ADR-784): issue a draft, void it,
 * edit its due day and description, attach or download its file. It was the
 * ledger panel's invoice card; the panel and the profile now share it.
 * `canManage` (manage_billing) gates issuing, voiding and editing.
 */
export function ChargeDetails({
  invoice,
  token,
  canManage,
  onUploaded,
}: {
  invoice: FinanceRecord;
  token: string;
  canManage: boolean;
  onUploaded: () => void;
}) {
  const uiLocale = useUiLocale();
  const i18n = useUiTranslations();
  const invoiceId = field(invoice, "id");
  const status = field(invoice, "status");
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [downloading, setDownloading] = useState(false);
  const [editing, setEditing] = useState(false);
  const [editDueDate, setEditDueDate] = useState(field(invoice, "due_date"));
  const [editNotes, setEditNotes] = useState(field(invoice, "notes"));
  const [saving, setSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [actioning, setActioning] = useState(false);
  const invoiceParams = (invoice.params as Record<string, string> | null) ?? {};
  const hasFile = Boolean(invoiceParams.file_key);

  async function handleIssue() {
    setActioning(true);
    try {
      await issueFinanceInvoice(token, invoiceId);
      onUploaded();
    } finally {
      setActioning(false);
    }
  }

  async function handleVoid() {
    if (!confirm(i18n("voidThisInvoiceThisCannotBeUndone571b60e"))) return;
    setActioning(true);
    try {
      await voidFinanceInvoice(token, invoiceId);
      onUploaded();
    } finally {
      setActioning(false);
    }
  }

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    setUploadError(null);
    try {
      const { upload_url, content_type } = await getInvoiceUploadUrl(
        token,
        invoiceId,
        file.name,
        file.type || "application/octet-stream",
      );
      const res = await fetch(upload_url, {
        method: "PUT",
        headers: { "Content-Type": content_type },
        body: file,
      });
      if (!res.ok) throw new Error(i18n("uploadFailedStatus", { status: res.status }));
      onUploaded();
    } catch (err) {
      setUploadError(err instanceof Error ? localizeError(err, i18n) : i18n("uploadFailedad0d060"));
    } finally {
      setUploading(false);
      if (fileInputRef.current) fileInputRef.current.value = "";
    }
  }

  async function handleDownload() {
    setDownloading(true);
    try {
      const { download_url, file_name } = await getInvoiceDownloadUrl(token, invoiceId);
      const a = document.createElement("a");
      a.href = download_url;
      a.download = file_name;
      a.target = "_blank";
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
    } finally {
      setDownloading(false);
    }
  }

  async function handleSaveEdit() {
    setSaving(true);
    setSaveError(null);
    try {
      await updateFinanceInvoice(token, invoiceId, {
        due_date: editDueDate || undefined,
        notes: editNotes || undefined,
      });
      setEditing(false);
      onUploaded();
    } catch (err) {
      setSaveError(err instanceof Error ? localizeError(err, i18n) : i18n("saveFailed0a44446"));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div
      className="rounded-[1.2rem] px-4 py-3 space-y-2"
      style={{ background: "var(--panel-muted)", border: "1px solid var(--border)" }}
    >
      <div className="flex flex-wrap items-center justify-between gap-3">
        <span className="text-xs" style={{ color: "var(--dim)" }}>
          {field(invoice, "invoice_number", invoiceId)} · {money(uiLocale, invoice.total_cents)}
        </span>
        <div className="flex flex-wrap items-center gap-2">
          <span
            className="text-xs font-semibold"
            style={{ color: statusColor(status) }}
          >
            <SemanticLabel value={status} />
          </span>

          {canManage && status === "draft" && (
            <button
              type="button"
              onClick={handleIssue}
              disabled={actioning}
              className="rounded-full px-2 py-0.5 text-xs font-semibold disabled:opacity-50 transition-opacity hover:opacity-80"
              style={{ background: "color-mix(in srgb, var(--success) 15%, transparent)", color: "var(--success)", border: "1px solid color-mix(in srgb, var(--success) 30%, transparent)" }}
            >
              {actioning ? "…" : i18n("issue73781a1")}
            </button>
          )}

          {canManage && status !== "void" && status !== "paid" && (
            <button
              type="button"
              onClick={handleVoid}
              disabled={actioning}
              className="rounded-full px-2 py-0.5 text-xs font-semibold disabled:opacity-50 transition-opacity hover:opacity-80"
              style={{ background: "color-mix(in srgb, var(--primary-strong) 10%, transparent)", color: "var(--primary-strong)", border: "1px solid color-mix(in srgb, var(--primary-strong) 25%, transparent)" }}
            >
              {i18n("void207c7c0")}
            </button>
          )}

          {canManage ? (
          <button
            type="button"
            onClick={() => {
              setEditing((v) => !v);
              setSaveError(null);
            }}
            className="text-xs hover:opacity-70 transition-opacity"
            style={{ color: "var(--dim)" }}
          >
            {editing ? i18n("cancel77dfd21") : i18n("edit5301648")}
          </button>
          ) : null}
        </div>
      </div>

      {/* Notes prominent display */}
      {!editing && (
        <div className="space-y-0.5">
          {field(invoice, "notes") ? (
            <p className="text-sm font-medium" style={{ color: "var(--text-soft)" }}>
              {field(invoice, "notes")}
            </p>
          ) : (
            <p className="text-xs italic" style={{ color: "var(--dim)" }}>{i18n("noDescriptionf354c94")}</p>
          )}
          <p className="text-xs" style={{ color: "var(--dim)" }}>
            {i18n("due7513f96")} {field(invoice, "due_date") || "—"}
          </p>
        </div>
      )}

      {/* Inline edit */}
      {editing && (
        <div className="space-y-2 pt-1">
          <div className="space-y-1">
            <label className="text-xs font-semibold uppercase tracking-[0.15em]" style={{ color: "var(--dim)" }}>
              {i18n("description55f8ebc")}
            </label>
            <input
              type="text"
              value={editNotes}
              onChange={(e) => setEditNotes(e.target.value)}
              placeholder={i18n("invoiceDescription4d26246")}
              className="w-full rounded-xl px-3 py-1.5 text-sm"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border-strong)", color: "var(--text)" }}
            />
          </div>
          <div className="space-y-1">
            <label className="text-xs font-semibold uppercase tracking-[0.15em]" style={{ color: "var(--dim)" }}>
              {i18n("dueDate4c1aeeb")}
            </label>
            <DateInput
              value={editDueDate}
              onValueChange={(value) => setEditDueDate(value)}
              className="w-full rounded-xl px-3 py-1.5 text-sm"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border-strong)", color: "var(--text)" }}
            />
          </div>
          {saveError && <ErrorNotice variant="field">{saveError}</ErrorNotice>}
          <button
            type="button"
            onClick={handleSaveEdit}
            disabled={saving}
            className="rounded-full px-3 py-1 text-xs font-semibold disabled:opacity-50 transition-opacity hover:opacity-80"
            style={{ background: "color-mix(in srgb, var(--success) 15%, transparent)", color: "var(--success)", border: "1px solid color-mix(in srgb, var(--success) 30%, transparent)" }}
          >
            {saving ? i18n("saving56a2285") : i18n("saveefc007a")}
          </button>
        </div>
      )}

      {/* File actions */}
      <div className="flex items-center gap-2 pt-1">
        <input
          ref={fileInputRef}
          type="file"
          accept="image/*,.pdf"
          className="hidden"
          onChange={handleFileChange}
        />
        <button
          type="button"
          onClick={() => fileInputRef.current?.click()}
          disabled={uploading}
          className="rounded-full px-2.5 py-1 text-xs font-semibold disabled:opacity-50 transition-opacity hover:opacity-70"
          style={{ background: "var(--border)", color: "var(--text-soft)", border: "1px solid var(--border-strong)" }}
        >
          {uploading ? i18n("uploadingd921a79") : hasFile ? i18n("replaceFile6d45b8c") : i18n("uploadFile503a3d8")}
        </button>

        {hasFile && (
          <button
            type="button"
            onClick={handleDownload}
            disabled={downloading}
            className="rounded-full px-2.5 py-1 text-xs font-semibold disabled:opacity-50 transition-opacity hover:opacity-70"
            style={{ background: "color-mix(in srgb, var(--success) 10%, transparent)", color: "var(--success)", border: "1px solid color-mix(in srgb, var(--success) 25%, transparent)" }}
          >
            {downloading ? "…" : i18n("downloada479c9c")}
          </button>
        )}

        {invoiceParams.file_name && (
          <span className="text-xs truncate max-w-[120px]" style={{ color: "var(--dim)" }}>
            {invoiceParams.file_name}
          </span>
        )}
      </div>

      {uploadError && (
        <ErrorNotice variant="field">
          {uploadError}
        </ErrorNotice>
      )}
    </div>
  );
}
