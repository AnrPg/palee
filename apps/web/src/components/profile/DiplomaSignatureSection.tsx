"use client";

import { useEffect, useRef, useState } from "react";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  deleteDiplomaSignature,
  getDiplomaSignature,
  getDiplomaSignatureImage,
  uploadDiplomaSignature,
  type DiplomaSignatureState,
} from "@/api/diploma-signature";
import { CollapsibleSection } from "@/components/profile/CollapsibleSection";
import { SIGNATURE_ACCEPT, prepareSignatureFile, readAsDataUrl } from "@/components/profile/diploma-signature-image";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";

const FIELD_ID = "diploma-signature-file";
const ERROR_ID = "diploma-signature-error";

function kilobytes(bytes: number) {
  return Math.round(bytes / 1024);
}

/**
 * Εγώ › Ρυθμίσεις › «Υπογραφή για διπλώματα» (ADR-377 addendum, option Γ):
 * a coach's own signature image, drawn above their name on the diplomas of
 * the promotions they award. Upload, preview, replace, remove. Shown only
 * to staff who award ranks; the image is only ever fetched by its owner.
 */
export function DiplomaSignatureSection() {
  const t = useTranslations("DiplomaSignature");
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  const [state, setState] = useState<DiplomaSignatureState | null>(null);
  // The preview's object URL, with the signature it shows.
  const [preview, setPreview] = useState<{ id: string; url: string } | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const signatureId = state?.signature?.id ?? null;

  useEffect(() => {
    if (!token) return;
    let active = true;
    getDiplomaSignature(token)
      .then((next) => active && setState(next))
      .catch(() => active && setState(null));
    return () => {
      active = false;
    };
  }, [token]);

  // The preview is the owner's own image, read with their session.
  useEffect(() => {
    if (!token || !signatureId) return;
    let active = true;
    let url: string | null = null;
    getDiplomaSignatureImage(token)
      .then((blob) => {
        if (!active || !(blob instanceof Blob) || typeof URL.createObjectURL !== "function") return;
        url = URL.createObjectURL(blob);
        setPreview({ id: signatureId, url });
      })
      .catch(() => undefined);
    return () => {
      active = false;
      if (url && typeof URL.revokeObjectURL === "function") URL.revokeObjectURL(url);
    };
  }, [token, signatureId]);

  if (!state?.eligible) return null;
  const { limits, signature } = state;
  const previewUrl = preview && signature && preview.id === signature.id ? preview.url : null;
  const name = (currentUser as { display_name?: string | null; nickname?: string } | null)?.display_name
    ?? (currentUser as { nickname?: string } | null)?.nickname
    ?? "";

  function serverError(cause: unknown) {
    const code = cause instanceof ApiError && typeof cause.payload?.code === "string" ? cause.payload.code : null;
    switch (code) {
      case "signature_unsupported_type":
      case "invalid_signature_image":
        return t("errorType");
      case "signature_too_large":
        return t("errorSize", { size: kilobytes(limits.max_bytes) });
      case "signature_too_small":
        return t("errorSmall", { width: limits.min_width, height: limits.min_height });
      case "signature_dimensions_too_large":
        return t("errorDimensions", { width: limits.max_width, height: limits.max_height });
      default:
        return t("errorSave");
    }
  }

  async function upload(file: File) {
    if (!token) return;
    setError(null);
    const prepared = await prepareSignatureFile(file, limits);
    if (!prepared.ok) {
      setError(prepared.error === "size" ? t("errorSize", { size: kilobytes(limits.max_bytes) }) : t("errorType"));
      return;
    }
    setPending(true);
    try {
      const stored = await uploadDiplomaSignature(token, await readAsDataUrl(prepared.blob));
      if (stored) setState((current) => (current ? { ...current, signature: stored } : current));
      else setError(t("errorSave"));
    } catch (cause) {
      setError(serverError(cause));
    } finally {
      setPending(false);
    }
  }

  async function remove() {
    if (!token) return;
    setError(null);
    setPending(true);
    try {
      await deleteDiplomaSignature(token);
      setState((current) => (current ? { ...current, signature: null } : current));
    } catch {
      setError(t("errorRemove"));
    } finally {
      setPending(false);
    }
  }

  return (
    <CollapsibleSection id="diploma-signature" title={t("title")} description={t("description")}>
      <div className="space-y-4">
        {signature ? (
          <figure className="mx-auto flex max-w-xs flex-col items-center gap-1" aria-label={t("previewLabel")}>
            <div className="flex h-20 w-full items-end justify-center rounded-xl px-3" style={{ background: "var(--panel-muted)" }}>
              {previewUrl ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={previewUrl} alt={t("previewAlt")} className="max-h-16 max-w-full object-contain" />
              ) : null}
            </div>
            <div className="w-full" style={{ borderTop: "1px solid var(--text)" }} />
            <figcaption className="text-xs" style={{ color: "var(--muted)" }}>
              {t("signedAs", { name })}
            </figcaption>
          </figure>
        ) : (
          <p className="text-sm" style={{ color: "var(--muted)" }}>
            {t("empty")}
          </p>
        )}

        <div className="space-y-1.5">
          <label htmlFor={FIELD_ID} className="block text-xs font-semibold uppercase tracking-[0.18em]" style={{ color: "var(--muted)" }}>
            {t("fieldLabel")}
          </label>
          <input
            ref={inputRef}
            id={FIELD_ID}
            type="file"
            accept={SIGNATURE_ACCEPT}
            className="sr-only"
            aria-describedby={error ? ERROR_ID : undefined}
            aria-invalid={error ? true : undefined}
            disabled={pending}
            onChange={(event) => {
              const file = event.target.files?.[0];
              event.target.value = "";
              if (file) void upload(file);
            }}
          />
          <div className="flex flex-wrap gap-3">
            <button
              type="button"
              disabled={pending}
              onClick={() => inputRef.current?.click()}
              className="rounded-xl px-6 py-2.5 text-sm font-semibold disabled:opacity-50"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            >
              {pending ? t("uploading") : signature ? t("replace") : t("upload")}
            </button>
            {signature ? (
              <button
                type="button"
                disabled={pending}
                onClick={() => void remove()}
                className="rounded-xl px-6 py-2.5 text-sm font-semibold disabled:opacity-50"
                style={{ border: "1px solid var(--border)", color: "var(--danger)" }}
              >
                {t("remove")}
              </button>
            ) : null}
          </div>
          {error ? (
            <ErrorNotice id={ERROR_ID} variant="field">
              {error}
            </ErrorNotice>
          ) : null}
          <p className="text-xs leading-5" style={{ color: "var(--muted)" }}>
            {t("help", { size: kilobytes(limits.max_bytes) })}
          </p>
          <p className="text-xs leading-5" style={{ color: "var(--muted)" }}>
            {t("snapshotNote")}
          </p>
        </div>
      </div>
    </CollapsibleSection>
  );
}
