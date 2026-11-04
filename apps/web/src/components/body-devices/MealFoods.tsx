"use client";

import { useEffect, useRef, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { ApiError } from "@/api/client";
import {
  createCustomFood,
  lookUpBarcode,
  readFoodLabel,
  type BarcodeLookup,
  type Food,
  type FoodLabelPrefill,
  type FoodPortion,
} from "@/api/body-devices";
import { useSession } from "@/components/session-provider";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { reencodeImage } from "@/lib/box-photo-upload";
import {
  addMealFood,
  FOOD_NUTRIENTS,
  FOOD_PORTIONS,
  normalizeBarcode,
  nutrientsFrom,
  type FoodNutrientKey,
  type MealFood,
} from "@/lib/body-devices";

type BarcodeDetectorLike = { detect(source: CanvasImageSource): Promise<{ rawValue: string }[]> };
type BarcodeDetectorConstructor = new (options: { formats: string[] }) => BarcodeDetectorLike;

function barcodeDetector(): BarcodeDetectorConstructor | null {
  if (typeof window === "undefined") return null;
  const candidate = (window as unknown as { BarcodeDetector?: BarcodeDetectorConstructor }).BarcodeDetector;
  return typeof candidate === "function" ? candidate : null;
}

const chip = (on: boolean) => ({
  background: on ? "var(--primary)" : "var(--panel-muted)",
  color: on ? "var(--primary-contrast)" : "var(--text)",
  border: "1px solid var(--border)",
});

/**
 * «Σάρωση barcode» inside a meal (ADR-376, mockups d9scan A and d9manual A):
 * a small button next to the photo; the product becomes a line of the meal
 * with a suggested hand portion. Never calories; grams per 100 g only when a
 * coach's plan sets macros and they are not hidden (the server decides).
 * When nothing is found, the same card turns into «Δικό μου τρόφιμο», which
 * «Φωτογραφία ετικέτας» can prefill from photos of the pack (ADR-421). A product
 * with a barcode can be shared with everyone (Palee and Open Food Facts) only by
 * ticking «Μοιράσου το»; a product members shared shows «από μέλη».
 */
export function MealFoods({ foods, onChange }: { foods: MealFood[]; onChange: (foods: MealFood[]) => void }) {
  const t = useTranslations("BodyDevices");
  const [scanning, setScanning] = useState(false);

  return (
    <div className="flex flex-col gap-2" data-testid="meal-foods">
      {foods.length > 0 ? (
        <ul className="flex flex-wrap gap-2">
          {foods.map((food, index) => (
            <li
              key={`${food.barcode ?? food.custom_food_id ?? food.name}-${index}`}
              className="flex items-center gap-2 rounded-full px-3 py-1 text-sm"
              style={{ background: "var(--panel-muted)", color: "var(--text)" }}
            >
              <span>{food.portion ? t("foods.withPortion", { name: food.name, portion: t(`foods.portion.${food.portion}`) }) : food.name}</span>
              <button
                type="button"
                aria-label={t("foods.remove", { name: food.name })}
                onClick={() => onChange(foods.filter((_, at) => at !== index))}
                style={{ color: "var(--dim)" }}
              >
                ×
              </button>
            </li>
          ))}
        </ul>
      ) : null}
      {scanning ? (
        <BarcodeCard
          onAdd={(food) => {
            onChange(addMealFood(foods, food));
            setScanning(false);
          }}
          onCancel={() => setScanning(false)}
        />
      ) : foods.length < 10 ? (
        <button
          type="button"
          onClick={() => setScanning(true)}
          className="flex min-h-11 items-center self-start rounded-2xl px-4 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("foods.scan")}
        </button>
      ) : null}
    </div>
  );
}

function BarcodeCard({ onAdd, onCancel }: { onAdd: (food: MealFood) => void; onCancel: () => void }) {
  const t = useTranslations("BodyDevices");
  const { tokens } = useSession();
  const token = tokens?.access_token ?? "";
  const [typed, setTyped] = useState("");
  const [typedError, setTypedError] = useState(false);
  const [result, setResult] = useState<BarcodeLookup | null>(null);
  const lookup = useMutation({
    mutationFn: (barcode: string) => lookUpBarcode(token, barcode),
    onSuccess: setResult,
  });

  function look(raw: string) {
    const barcode = normalizeBarcode(raw);
    if (!barcode) {
      setTypedError(true);
      return;
    }
    setTypedError(false);
    lookup.mutate(barcode);
  }

  if (result?.status === "found" && result.food) {
    return <FoundFood lookup={result} food={result.food} onAdd={onAdd} onCancel={onCancel} />;
  }
  if (result?.status === "manual") {
    return (
      <OwnFoodForm
        barcode={result.reason === "in_store_code" ? null : result.barcode}
        storeCode={result.reason === "in_store_code"}
        macrosVisible={result.macros_visible === true}
        labelReading={result.label_reading === true}
        onAdd={onAdd}
        onCancel={onCancel}
      />
    );
  }

  return (
    <section className="flex flex-col gap-3 rounded-2xl px-4 py-3" style={{ background: "var(--panel)", border: "1px solid var(--border)" }}>
      <Camera onCode={look} />
      <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
        {t("foods.typeIt")}
        <input
          inputMode="numeric"
          autoComplete="off"
          value={typed}
          aria-invalid={typedError}
          aria-describedby="barcode-error"
          onChange={(event) => setTyped(event.target.value)}
          className="min-h-11 rounded-2xl px-4"
          style={{ background: "var(--panel-muted)", border: `1px solid ${typedError ? "var(--danger)" : "var(--border)"}`, color: "var(--text)" }}
        />
        {typedError ? (
          <span id="barcode-error" className="text-xs font-normal" style={{ color: "var(--danger)" }}>{t("foods.invalidBarcode")}</span>
        ) : null}
      </label>
      {result?.status === "pending" ? <p className="text-xs" style={{ color: "var(--dim)" }}>{t("foods.pending")}</p> : null}
      {lookup.isError ? <ErrorNotice>{t("errorGeneric")}</ErrorNotice> : null}
      <div className="flex items-center gap-3">
        <button
          type="button"
          disabled={lookup.isPending || typed.trim() === ""}
          onClick={() => look(typed)}
          className="min-h-11 rounded-2xl px-4 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("foods.find")}
        </button>
        <button type="button" onClick={onCancel} className="text-sm font-semibold" style={{ color: "var(--dim)" }}>
          {t("cancel")}
        </button>
      </div>
    </section>
  );
}

/** The phone's camera when the browser can read barcodes; nothing otherwise (typing still works). */
function Camera({ onCode }: { onCode: (code: string) => void }) {
  const t = useTranslations("BodyDevices");
  const video = useRef<HTMLVideoElement>(null);
  const [available] = useState(() => barcodeDetector() !== null);
  const found = useRef(onCode);
  useEffect(() => {
    found.current = onCode;
  }, [onCode]);

  useEffect(() => {
    const Detector = barcodeDetector();
    if (!Detector || !navigator.mediaDevices?.getUserMedia) return;
    let stream: MediaStream | null = null;
    let timer: number | null = null;
    let stopped = false;
    const detector = new Detector({ formats: ["ean_13", "ean_8", "upc_a", "upc_e"] });
    void navigator.mediaDevices
      .getUserMedia({ video: { facingMode: "environment" } })
      .then((media) => {
        if (stopped) {
          media.getTracks().forEach((track) => track.stop());
          return;
        }
        stream = media;
        if (video.current) {
          video.current.srcObject = media;
          void video.current.play();
        }
        timer = window.setInterval(async () => {
          if (!video.current || video.current.readyState < 2) return;
          const codes = await detector.detect(video.current).catch(() => []);
          if (codes[0]?.rawValue) found.current(codes[0].rawValue);
        }, 400);
      })
      .catch(() => undefined);
    return () => {
      stopped = true;
      if (timer !== null) window.clearInterval(timer);
      stream?.getTracks().forEach((track) => track.stop());
    };
  }, []);

  if (!available) return null;
  return (
    <div className="flex flex-col gap-1">
      <video ref={video} muted playsInline className="aspect-video w-full rounded-xl object-cover" style={{ background: "var(--panel-muted)" }} />
      <span className="text-xs" style={{ color: "var(--dim)" }}>{t("foods.aim")}</span>
    </div>
  );
}

function FoundFood({ lookup, food, onAdd, onCancel }: { lookup: BarcodeLookup; food: Food; onAdd: (food: MealFood) => void; onCancel: () => void }) {
  const t = useTranslations("BodyDevices");
  const [portion, setPortion] = useState<FoodPortion | null>(food.portion_hint ?? null);
  const nutrients = lookup.macros_visible ? food.nutrients : null;
  const sourceName = lookup.source === "palee_members" ? t("foods.membersSource") : (lookup.attribution?.source ?? "");
  return (
    <section
      data-testid="barcode-found"
      className="flex flex-col gap-3 rounded-2xl px-4 py-3"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div className="flex items-start justify-between gap-3">
        <span className="text-sm font-bold" style={{ color: "var(--text)" }}>{food.name}</span>
        {food.brand ? <span className="shrink-0 text-xs" style={{ color: "var(--text-soft)" }}>{food.brand}</span> : null}
      </div>
      <PortionChips label={t("foods.countsAs")} value={portion} onChange={setPortion} />
      {nutrients ? (
        <p className="text-xs" style={{ color: "var(--text-soft)" }}>
          {t("foods.per100g", {
            protein: nutrients.proteins ?? 0,
            carbs: nutrients.carbohydrates ?? 0,
            fat: nutrients.fat ?? 0,
          })}
        </p>
      ) : null}
      {lookup.source === "palee_members" ? (
        <span
          data-testid="from-members"
          className="self-start rounded-full px-2 py-0.5 text-xs font-semibold"
          style={{ background: "var(--panel-muted)", color: "var(--text-soft)", border: "1px solid var(--border)" }}
        >
          {t("foods.fromMembers")}
        </span>
      ) : null}
      {lookup.attribution?.source ? (
        lookup.attribution.url || lookup.attribution.licence_url ? (
          <a
            href={lookup.attribution.url ?? lookup.attribution.licence_url ?? undefined}
            target="_blank"
            rel="noreferrer"
            className="text-xs"
            style={{ color: "var(--dim)" }}
          >
            {t("foods.source", { source: sourceName, licence: lookup.attribution.licence })}
          </a>
        ) : (
          <span className="text-xs" style={{ color: "var(--dim)" }}>
            {t("foods.source", { source: sourceName, licence: lookup.attribution.licence })}
          </span>
        )
      ) : null}
      <div className="flex items-center gap-3">
        <button
          type="button"
          onClick={() =>
            onAdd({
              name: food.name,
              ...(food.barcode ? { barcode: food.barcode } : {}),
              ...(food.id ? { custom_food_id: food.id } : {}),
              ...(portion ? { portion } : {}),
            })
          }
          className="min-h-11 rounded-2xl px-4 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("foods.add")}
        </button>
        <button type="button" onClick={onCancel} className="text-sm font-semibold" style={{ color: "var(--dim)" }}>
          {t("cancel")}
        </button>
      </div>
    </section>
  );
}

function PortionChips({ label, value, onChange }: { label: string; value: FoodPortion | null; onChange: (value: FoodPortion | null) => void }) {
  const t = useTranslations("BodyDevices");
  return (
    <div className="flex flex-col gap-1">
      <span className="text-xs" style={{ color: "var(--text-soft)" }}>{label}</span>
      <div className="flex flex-wrap gap-2" role="group" aria-label={label}>
        {FOOD_PORTIONS.map((key) => (
          <button
            key={key}
            type="button"
            aria-pressed={value === key}
            onClick={() => onChange(value === key ? null : key)}
            className="min-h-9 rounded-full px-3 text-sm font-semibold"
            style={chip(value === key)}
          >
            {t(`foods.portion.${key}`)}
          </button>
        ))}
      </div>
    </div>
  );
}

type NutrientFields = Partial<Record<FoodNutrientKey, string>>;

function OwnFoodForm({
  barcode,
  storeCode,
  macrosVisible,
  labelReading,
  onAdd,
  onCancel,
}: {
  barcode: string | null;
  storeCode: boolean;
  macrosVisible: boolean;
  labelReading: boolean;
  onAdd: (food: MealFood) => void;
  onCancel: () => void;
}) {
  const t = useTranslations("BodyDevices");
  const { tokens } = useSession();
  const [name, setName] = useState("");
  const [nameError, setNameError] = useState(false);
  const [portion, setPortion] = useState<FoodPortion | null>(null);
  const [advanced, setAdvanced] = useState(false);
  const [brand, setBrand] = useState("");
  const [serving, setServing] = useState("");
  const [nutrients, setNutrients] = useState<NutrientFields>({});
  const [nutrientErrors, setNutrientErrors] = useState<FoodNutrientKey[]>([]);
  // ADR-421 addendum: an explicit choice, never ticked for the person; only a product barcode.
  const shareable = barcode !== null && !storeCode;
  const [share, setShare] = useState(false);
  const save = useMutation({
    mutationFn: (grams: Partial<Record<FoodNutrientKey, number>>) =>
      createCustomFood(tokens!.access_token, {
        name: name.trim(),
        ...(barcode ? { barcode } : {}),
        ...(brand.trim() ? { brand: brand.trim() } : {}),
        ...(serving.trim() ? { serving_label: serving.trim() } : {}),
        ...(portion ? { portion_hint: portion } : {}),
        ...(Object.keys(grams).length > 0 ? { nutrients: grams } : {}),
        ...(shareable && share ? { share: true } : {}),
      }),
    onSuccess: (food) => onAdd({ name: food.name, ...(food.id ? { custom_food_id: food.id } : {}), ...(portion ? { portion } : {}) }),
  });
  const field = { background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" };

  function prefill(food: FoodLabelPrefill) {
    if (food.name) {
      setName(food.name);
      setNameError(false);
    }
    if (food.brand) setBrand(food.brand);
    if (food.serving_label) setServing(food.serving_label);
    if (food.portion_hint) setPortion(food.portion_hint);
    const read = food.nutrients ?? {};
    const filled: NutrientFields = {};
    for (const key of FOOD_NUTRIENTS) {
      const value = read[key];
      if (typeof value === "number") filled[key] = String(value);
    }
    if (macrosVisible) {
      setNutrients(filled);
      setNutrientErrors([]);
    }
    if (food.brand || food.serving_label || (macrosVisible && Object.keys(filled).length > 0)) setAdvanced(true);
  }

  return (
    <section
      data-testid="own-food"
      className="flex flex-col gap-3 rounded-2xl px-4 py-3"
      style={{ background: "var(--panel)", border: "1px solid var(--border)" }}
    >
      <div>
        <p className="text-sm font-bold" style={{ color: "var(--text)" }}>{storeCode ? t("foods.storeCodeTitle") : t("foods.notFoundTitle")}</p>
        <p className="text-xs" style={{ color: "var(--text-soft)" }}>{storeCode ? t("foods.storeCodeHint") : t("foods.notFoundHint")}</p>
      </div>
      {labelReading ? <LabelPhoto onRead={prefill} /> : null}
      <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
        {t("foods.name")}
        <input
          value={name}
          maxLength={120}
          aria-invalid={nameError}
          onChange={(event) => {
            setName(event.target.value);
            setNameError(false);
          }}
          className="min-h-11 rounded-2xl px-4"
          style={{ ...field, border: `1px solid ${nameError ? "var(--danger)" : "var(--border)"}` }}
        />
        {nameError ? <span className="text-xs font-normal" style={{ color: "var(--danger)" }}>{t("foods.nameRequired")}</span> : null}
      </label>
      <PortionChips label={t("foods.countsAs")} value={portion} onChange={setPortion} />
      <button type="button" aria-expanded={advanced} onClick={() => setAdvanced(!advanced)} className="self-start text-sm font-semibold" style={{ color: "var(--dim)" }}>
        {t("advanced")}
      </button>
      {advanced ? (
        <div className="flex flex-col gap-3">
          <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("foods.brand")}
            <input value={brand} maxLength={120} onChange={(event) => setBrand(event.target.value)} className="min-h-11 rounded-2xl px-4" style={field} />
          </label>
          <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
            {t("foods.serving")}
            <input value={serving} maxLength={60} onChange={(event) => setServing(event.target.value)} className="min-h-11 rounded-2xl px-4" style={field} />
          </label>
          {macrosVisible ? (
            <fieldset className="flex flex-col gap-2" data-testid="own-food-nutrients">
              <legend className="text-xs" style={{ color: "var(--text-soft)" }}>{t("foods.per100gTitle")}</legend>
              <div className="grid grid-cols-2 gap-2">
                {FOOD_NUTRIENTS.map((key) => {
                  const invalid = nutrientErrors.includes(key);
                  return (
                    <label key={key} className="flex flex-col gap-1 text-xs font-semibold" style={{ color: "var(--text)" }}>
                      {t(`foods.nutrient.${key}`)}
                      <input
                        inputMode="decimal"
                        autoComplete="off"
                        value={nutrients[key] ?? ""}
                        aria-invalid={invalid}
                        onChange={(event) => {
                          setNutrients({ ...nutrients, [key]: event.target.value });
                          setNutrientErrors(nutrientErrors.filter((entry) => entry !== key));
                        }}
                        className="min-h-11 rounded-2xl px-3 text-sm"
                        style={{ ...field, border: `1px solid ${invalid ? "var(--danger)" : "var(--border)"}` }}
                      />
                      {invalid ? <span className="font-normal" style={{ color: "var(--danger)" }}>{t("foods.nutrientInvalid")}</span> : null}
                    </label>
                  );
                })}
              </div>
            </fieldset>
          ) : null}
        </div>
      ) : null}
      {shareable ? (
        <label className="flex items-start gap-3 text-sm font-semibold" style={{ color: "var(--text)" }}>
          <input
            type="checkbox"
            checked={share}
            onChange={(event) => setShare(event.target.checked)}
            aria-describedby="own-food-share-help"
            data-testid="own-food-share"
            className="mt-1 h-5 w-5 shrink-0"
            style={{ accentColor: "var(--primary)" }}
          />
          <span className="flex flex-col gap-1">
            {t("foods.share")}
            <span id="own-food-share-help" className="text-xs font-normal" style={{ color: "var(--dim)" }}>
              {t("foods.shareHelp")}
            </span>
          </span>
        </label>
      ) : null}
      {shareable && share ? null : <p className="text-xs" style={{ color: "var(--dim)" }}>{t("foods.staysYours")}</p>}
      {save.isError ? <ErrorNotice>{t("errorGeneric")}</ErrorNotice> : null}
      <div className="flex items-center gap-3">
        <button
          type="button"
          disabled={save.isPending}
          onClick={() => {
            const grams = macrosVisible ? nutrientsFrom(nutrients) : { nutrients: {}, invalid: [] };
            if (!name.trim()) setNameError(true);
            if (grams.invalid.length > 0) {
              setNutrientErrors(grams.invalid);
              setAdvanced(true);
            }
            if (!name.trim() || grams.invalid.length > 0) return;
            save.mutate(grams.nutrients);
          }}
          className="min-h-11 rounded-2xl px-4 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("foods.saveOwn")}
        </button>
        <button type="button" onClick={onCancel} className="text-sm font-semibold" style={{ color: "var(--dim)" }}>
          {t("cancel")}
        </button>
      </div>
    </section>
  );
}

/**
 * «Φωτογραφία ετικέτας» (ADR-421): the front and the nutrition table, re-encoded
 * in the browser (no EXIF) and read by the server, which keeps neither photo.
 * The person checks the prefilled form before saving.
 */
function LabelPhoto({ onRead }: { onRead: (food: FoodLabelPrefill) => void }) {
  const t = useTranslations("BodyDevices");
  const { tokens } = useSession();
  const [open, setOpen] = useState(false);
  const [front, setFront] = useState<File | null>(null);
  const [table, setTable] = useState<File | null>(null);
  const [missing, setMissing] = useState(false);
  const read = useMutation({
    mutationFn: async () => {
      const [frontBlob, tableBlob] = await Promise.all([front ? reencodeImage(front) : null, table ? reencodeImage(table) : null]);
      return readFoodLabel(tokens!.access_token, { front: frontBlob, nutrition: tableBlob });
    },
    onSuccess: (reading) => {
      onRead(reading.food);
      setOpen(false);
    },
  });
  const error = read.error;
  const message =
    error instanceof ApiError && error.status === 503 ? t("foods.labelUnavailable") : error ? t("foods.labelUnreadable") : null;

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="flex min-h-11 items-center self-start rounded-2xl px-4 text-sm font-semibold"
        style={{ border: "1px solid var(--border)", color: "var(--text)" }}
      >
        {t("foods.labelPhoto")}
      </button>
    );
  }

  const picker = (label: string, file: File | null, onPick: (file: File | null) => void) => (
    <label className="flex flex-col gap-1 text-sm font-semibold" style={{ color: "var(--text)" }}>
      {label}
      <input
        type="file"
        accept="image/*"
        capture="environment"
        onChange={(event) => {
          onPick(event.target.files?.[0] ?? null);
          setMissing(false);
          read.reset();
        }}
        className="text-xs font-normal"
        style={{ color: "var(--text-soft)" }}
      />
      {file ? <span className="text-xs font-normal" style={{ color: "var(--dim)" }}>{file.name}</span> : null}
    </label>
  );

  return (
    <div className="flex flex-col gap-2 rounded-2xl px-3 py-3" data-testid="label-photo" style={{ background: "var(--panel-muted)" }}>
      {picker(t("foods.labelFront"), front, setFront)}
      {picker(t("foods.labelTable"), table, setTable)}
      <p className="text-xs" style={{ color: "var(--dim)" }}>{t("foods.labelHint")}</p>
      {missing ? (
        <span className="text-xs" style={{ color: "var(--danger)" }}>{t("foods.labelNeedPhoto")}</span>
      ) : message ? (
        <span className="text-xs" style={{ color: "var(--danger)" }}>{message}</span>
      ) : null}
      <div className="flex items-center gap-3">
        <button
          type="button"
          disabled={read.isPending}
          onClick={() => {
            if (!front && !table) {
              setMissing(true);
              return;
            }
            read.mutate();
          }}
          className="min-h-11 rounded-2xl px-4 text-sm font-semibold"
          style={{ border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {read.isPending ? t("foods.labelReading") : t("foods.labelRead")}
        </button>
        <button type="button" onClick={() => setOpen(false)} className="text-sm font-semibold" style={{ color: "var(--dim)" }}>
          {t("cancel")}
        </button>
      </div>
    </div>
  );
}
