"use client";

import { useQuery } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useRef, useState } from "react";

import type { FinanceRecord } from "@/api/finance";
import { fetchAdminSettings } from "@/api/settings";
import { useSession } from "@/components/session-provider";
import { PackageActivationChoice } from "./PackageActivationChoice";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { Popover } from "@/components/ui/Popover";
import { Select } from "@/components/ui/Select";
import { localizeError } from "@/i18n/presentation";
import { useUiTranslations } from "@/i18n/ui";

interface Props {
  userId: string;
  currentCode: string | null;
  currentLabel?: string | null;
  packages: FinanceRecord[];
  pending: boolean;
  /** Resolves once the package is assigned; a rejection keeps the menu open with the reason. */
  onAssign: (packageId: string) => Promise<unknown>;
  /** ADR-660: «Αφαίρεση πακέτου…» for the package the member holds now. */
  onRemove?: () => void;
  /** ADR-795 «Τα πήρα τώρα»: after the package is given, record the money that was really taken. */
  onReceive?: () => void;
  /** ADR-795 «Χωρίς χρέωση»: an ADR-612 free package, with who and why. */
  onGiveFree?: (packageId: string, reason: string | null) => Promise<unknown>;
}

type Step = "pick" | "money";

/**
 * The ledger's «Ενεργοποίηση πακέτου» menu for a πακέτο συνδρομής (ADR-795,
 * 2A): pick the package, then say what happened with its money: «Θα πληρώσει
 * αργότερα» (it is owed), «Τα πήρα τώρα» (the payment is recorded next) or
 * «Χωρίς χρέωση» (a free package). Giving a package never invents a payment.
 * It is a ui/Popover, so a press on the package list (its own portal) counts
 * as inside the menu.
 */
export function InlineAssignPackage({ currentCode, currentLabel, packages, pending, onAssign, onRemove, onReceive, onGiveFree }: Props) {
  const i18n = useUiTranslations();
  const t = useTranslations("PackageRemoval");
  const ta = useTranslations("PackageActivation");
  const token = useSession().tokens?.access_token ?? null;
  const [open, setOpen] = useState(false);
  const [selectedId, setSelectedId] = useState("");
  const [step, setStep] = useState<Step>("pick");
  const [error, setError] = useState<unknown>(null);
  const ref = useRef<HTMLDivElement>(null);
  const settingsQuery = useQuery({
    queryKey: ["admin", "settings"],
    queryFn: () => fetchAdminSettings(token!),
    enabled: open && Boolean(token),
  });
  const startsWith = settingsQuery.data?.finance?.package_starts_with;
  const selected = packages.find((pkg) => String(pkg.id) === selectedId) ?? null;
  const priceCents = selected && typeof selected.base_price_cents === "number" ? selected.base_price_cents : 0;

  function close() {
    setOpen(false);
    setSelectedId("");
    setStep("pick");
    setError(null);
  }

  async function run(action: () => Promise<unknown>, after?: () => void): Promise<void> {
    setError(null);
    try {
      await action();
      close();
      after?.();
    } catch (failure) {
      setError(failure);
    }
  }

  function handleNext() {
    if (!selectedId) return;
    // A package that costs nothing has no money to ask about.
    if (priceCents > 0) setStep("money");
    else void run(() => onAssign(selectedId));
  }

  return (
    <div ref={ref} className="relative inline-block">
      {currentLabel || currentCode ? (
        <button
          type="button"
          onClick={() => (open ? close() : setOpen(true))}
          className="group flex items-center gap-1 rounded-full px-3 py-1 text-xs font-semibold transition-opacity hover:opacity-70"
          style={{ background: "var(--border)", color: "var(--text-soft)" }}
          title={i18n("changePackage8621cbc")}
        >
          {currentLabel || currentCode}
          <span className="opacity-0 group-hover:opacity-60 transition-opacity text-[10px]">✎</span>
        </button>
      ) : (
        <button
          type="button"
          onClick={() => (open ? close() : setOpen(true))}
          className="rounded-full px-3 py-1 text-xs font-semibold transition-opacity hover:opacity-80"
          style={{
            border: "1px solid color-mix(in srgb, var(--primary) 35%, transparent)",
            color: "var(--dim)",
            background: "transparent",
          }}
        >
          {i18n("assign23afc22")}
        </button>
      )}

      <Popover
        anchorRef={ref}
        open={open}
        onClose={close}
        minWidth={240}
        role="dialog"
        ariaLabel={i18n("assign2444928")}
        className="rounded-xl p-3 shadow-xl"
        style={{
          background: "var(--panel-raised)",
          border: "1px solid var(--border-strong)",
          boxShadow: "var(--shadow-md)",
        }}
      >
        {step === "pick" ? (
          <>
        <Select
          value={selectedId}
          onValueChange={(value) => setSelectedId(value)}
          className="mb-3 w-full rounded-lg px-3 py-2.5 text-sm"
          style={{ background: "var(--panel)", color: "var(--text-soft)", border: "1px solid var(--border-strong)" }}
        >
          <option value="">{i18n("selectPackage02bf832")}</option>
          {packages.map((pkg) => (
            <option
              key={String(pkg.id)}
              value={String(pkg.id)}
              disabled={pkg.active === false}
            >
              {String(pkg.name || pkg.code)}
              {pkg.active === false ? i18n("inactive0e9b582") : ""}
            </option>
          ))}
        </Select>
        <button
          type="button"
          onClick={handleNext}
          disabled={!selectedId || pending}
          className="w-full rounded-lg px-3 py-2.5 text-sm font-semibold transition-opacity disabled:opacity-40"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
          data-testid="package-activate-next"
        >
          {pending ? i18n("assigning4d16a1a") : ta("activate")}
        </button>
        {startsWith ? (
          <p className="mt-2 text-xs leading-5" style={{ color: "var(--dim)" }} data-testid="package-activate-starts">
            {startsWith === "payment" ? ta("startsOnPayment") : ta("startsFirstSession")}
          </p>
        ) : null}
          </>
        ) : null}

        {step === "money" && selected ? (
          <PackageActivationChoice
            packageName={String(selected.name || selected.code)}
            priceCents={priceCents}
            pending={pending}
            onLater={() => run(() => onAssign(selectedId))}
            onPaidNow={onReceive ? () => run(() => onAssign(selectedId), onReceive) : undefined}
            onFree={onGiveFree ? (reason) => run(() => onGiveFree(selectedId, reason)) : undefined}
            onBack={() => setStep("pick")}
          />
        ) : null}

        {error ? (
          <ErrorNotice variant="field" className="mt-2">
            {localizeError(error, i18n)}
          </ErrorNotice>
        ) : null}
        {onRemove && (currentLabel || currentCode) ? (
          <button
            type="button"
            onClick={() => {
              close();
              onRemove();
            }}
            className="mt-3 w-full pt-3 text-start text-sm font-semibold"
            style={{ borderTop: "1px solid var(--border)", color: "var(--danger)" }}
            data-testid="package-remove-open"
          >
            {t("open")}
          </button>
        ) : null}
      </Popover>
    </div>
  );
}

