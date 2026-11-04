"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useEffect, useId, useRef, useState, type KeyboardEvent, type PointerEvent as ReactPointerEvent } from "react";

import { ApiError } from "@/api/client";
import { removeProgrammeCover } from "@/api/programme-covers";
import { staffProgrammeKey, type StaffProgramme } from "@/api/programmes";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useProgrammeError } from "@/components/programmes/programme-ui";

import {
  brightnessTo,
  COVER_MAX_BRIGHTNESS,
  COVER_MIN_BRIGHTNESS,
  fromApiEdit,
  INITIAL_COVER_EDIT,
  isTooSmall,
  maxZoom,
  panBy,
  rotateClockwise,
  zoomTo,
  type CoverEdit,
  type CoverEditInput,
  type ImageSize,
} from "./cover-edit-model";
import { CoverUploadError, drawCover, loadCoverImage, saveCover, workingSize, type CoverImage } from "./cover-upload";

/** The preview canvas (16:9); the saved cover is rendered at the photo's own resolution. */
const PREVIEW = { width: 960, height: 540 };
const KEY_STEP = 0.05;

/**
 * «Εξώφυλλο» in the programme's details (ADR-541): the cover photo, or the
 * theme's colour strip without one. «Ανέβασμα φωτογραφίας» opens the editor
 * (crop to 16:9 by dragging, zoom, turn by 90°, brightness); «Επεξεργασία»
 * opens it again on the stored original; «Αφαίρεση» goes back to the strip.
 */
export function ProgrammeCoverField({ programme, token }: { programme: StaffProgramme; token: string }) {
  const t = useTranslations("Programmes.editor2");
  const tp = useTranslations("Programmes");
  const queryClient = useQueryClient();
  const programmeError = useProgrammeError();
  const fileRef = useRef<HTMLInputElement>(null);
  const [source, setSource] = useState<{ kind: "picked"; file: File } | { kind: "stored" } | null>(null);
  const [confirmRemove, setConfirmRemove] = useState(false);
  const cover = programme.cover ?? null;
  const url = programme.cover_url ?? cover?.url ?? null;

  const remove = useMutation({
    mutationFn: () => removeProgrammeCover(token, programme.id),
    onSuccess: (saved) => {
      queryClient.setQueryData(staffProgrammeKey(programme.id), saved);
      setConfirmRemove(false);
    },
  });

  return (
    <section className="flex flex-col gap-2" aria-labelledby="programme-cover-label" data-testid="programme-cover">
      <h3 id="programme-cover-label" className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("cover")}</h3>
      <div className="relative aspect-video w-full overflow-hidden rounded-2xl" style={{ background: "linear-gradient(135deg, var(--primary), var(--spark))" }}>
        {url ? (
          // A user upload on the public media host; next/image would need every host configured.
          // eslint-disable-next-line @next/next/no-img-element
          <img src={url} alt={t("coverAlt", { title: programme.title })} className="h-full w-full object-cover" />
        ) : null}
      </div>
      {!url ? <p className="text-xs" style={{ color: "var(--muted)" }}>{t("coverHint")}</p> : null}
      <div className="flex flex-wrap gap-2">
        <input
          ref={fileRef}
          type="file"
          accept="image/*"
          className="sr-only"
          tabIndex={-1}
          aria-hidden="true"
          onChange={(event) => {
            const file = event.target.files?.[0];
            event.target.value = "";
            if (file) setSource({ kind: "picked", file });
          }}
          data-testid="programme-cover-file"
        />
        <CoverButton onClick={() => fileRef.current?.click()} testId="programme-cover-upload">
          {url ? t("coverReplace") : t("coverUpload")}
        </CoverButton>
        {cover?.original_url ? (
          <CoverButton onClick={() => setSource({ kind: "stored" })} testId="programme-cover-edit">{t("coverEdit")}</CoverButton>
        ) : null}
        {url ? (
          <CoverButton onClick={() => setConfirmRemove(true)} tone="danger" testId="programme-cover-remove">{t("coverRemove")}</CoverButton>
        ) : null}
      </div>

      {source ? (
        <CoverEditor
          key={source.kind === "picked" ? `${source.file.name}-${source.file.lastModified}` : source.kind}
          programmeId={programme.id}
          token={token}
          source={source.kind === "picked" ? source.file : (cover?.original_url ?? "")}
          storedEdit={source.kind === "picked" ? null : (cover?.edit ?? null)}
          originalMediaId={source.kind === "picked" ? null : (cover?.original_media_id ?? null)}
          onClose={() => setSource(null)}
          onSaved={(saved) => {
            queryClient.setQueryData(staffProgrammeKey(programme.id), saved);
            setSource(null);
          }}
        />
      ) : null}

      {confirmRemove ? (
        <Dialog
          onClose={() => setConfirmRemove(false)}
          dismissible={!remove.isPending}
          title={t("coverRemoveTitle")}
          size="sm"
          variant="center"
          testId="programme-cover-remove-dialog"
          footer={
            <>
              <DialogButton onClick={() => setConfirmRemove(false)} disabled={remove.isPending}>{tp("cancel")}</DialogButton>
              <DialogButton tone="danger" onClick={() => remove.mutate()} disabled={remove.isPending} testId="programme-cover-remove-confirm">
                {t("coverRemove")}
              </DialogButton>
            </>
          }
        >
          <p className="text-sm" style={{ color: "var(--text-soft)" }}>{t("coverRemoveBody")}</p>
          {remove.isError ? <ErrorNotice variant="field" className="mt-2">{programmeError(remove.error)}</ErrorNotice> : null}
        </Dialog>
      ) : null}
    </section>
  );
}

function CoverButton({ children, onClick, tone, testId }: { children: React.ReactNode; onClick: () => void; tone?: "danger"; testId?: string }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="min-h-11 rounded-full px-4 text-sm font-semibold"
      style={{ border: "1px solid var(--border)", color: tone === "danger" ? "var(--danger)" : "var(--text-soft)" }}
      data-testid={testId}
    >
      {children}
    </button>
  );
}

type Loaded = { image: CoverImage; size: ImageSize };

export function CoverEditor({
  programmeId,
  token,
  source,
  storedEdit,
  originalMediaId,
  onClose,
  onSaved,
}: {
  programmeId: string;
  token: string;
  /** A newly picked photo, or the stored original's URL. */
  source: File | string;
  storedEdit: CoverEditInput | null;
  /** Set when editing again: the original is not uploaded twice. */
  originalMediaId: string | null;
  onClose: () => void;
  onSaved: (programme: StaffProgramme) => void;
}) {
  const t = useTranslations("Programmes.editor2");
  const tp = useTranslations("Programmes");
  const programmeError = useProgrammeError();
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [loaded, setLoaded] = useState<Loaded | null>(null);
  const [edit, setEdit] = useState<CoverEdit>(INITIAL_COVER_EDIT);
  const [loadError, setLoadError] = useState<"load" | "small" | null>(null);
  const zoomId = useId();
  const brightnessId = useId();
  const errorId = useId();

  useEffect(() => {
    const controller = new AbortController();
    loadCoverImage(source, controller.signal)
      .then((image) => {
        if (controller.signal.aborted) return;
        const size = workingSize(image);
        if (isTooSmall(size)) {
          setLoadError("small");
          return;
        }
        setLoaded({ image, size });
        setEdit(fromApiEdit(size, storedEdit));
      })
      .catch(() => {
        if (!controller.signal.aborted) setLoadError("load");
      });
    return () => controller.abort();
  }, [source, storedEdit]);

  useEffect(() => {
    if (loaded && canvasRef.current) drawCover(canvasRef.current, loaded.image, loaded.size, edit);
  }, [loaded, edit]);

  const save = useMutation({
    mutationFn: () => saveCover(token, programmeId, { image: loaded!.image, size: loaded!.size, edit, originalMediaId }),
    onSuccess: onSaved,
  });

  const update = (next: (size: ImageSize, current: CoverEdit) => CoverEdit) => {
    if (loaded) setEdit((current) => next(loaded.size, current));
  };
  const gestures = useDragGestures({
    onPan: (dx, dy) => update((size, current) => panBy(size, current, dx, dy)),
    onZoom: (factor) => update((size, current) => zoomTo(size, current, current.zoom * factor)),
  });

  function onPreviewKey(event: KeyboardEvent<HTMLDivElement>) {
    const moves: Record<string, [number, number]> = {
      ArrowLeft: [KEY_STEP, 0],
      ArrowRight: [-KEY_STEP, 0],
      ArrowUp: [0, KEY_STEP],
      ArrowDown: [0, -KEY_STEP],
    };
    const move = moves[event.key];
    if (!move) return;
    event.preventDefault();
    update((size, current) => panBy(size, current, move[0], move[1]));
  }

  const ready = loaded !== null;
  const errorText =
    loadError === "small"
      ? t("coverTooSmall")
      : loadError === "load"
        ? t("coverLoadFailed")
        : save.isError
          ? coverError(save.error)
          : null;

  function coverError(error: unknown) {
    if (error instanceof CoverUploadError) return error.reason === "unsupported" ? t("coverLoadFailed") : t("coverUploadFailed");
    if (error instanceof ApiError && (error.payload.code === "invalid_cover_size" || error.payload.code === "invalid_cover_edit")) return t("coverTooSmall");
    return programmeError(error);
  }

  const zoomMax = loaded ? maxZoom(loaded.size, edit.rotation) : 1;

  return (
    <Dialog
      onClose={onClose}
      dismissible={!save.isPending}
      title={t("coverEditorTitle")}
      description={t("coverGestureHint")}
      size="2xl"
      variant="screen"
      testId="programme-cover-editor"
      footer={
        <>
          <DialogButton onClick={onClose} disabled={save.isPending}>{tp("cancel")}</DialogButton>
          <DialogButton tone="primary" onClick={() => save.mutate()} disabled={!ready || save.isPending} testId="programme-cover-save">
            {save.isPending ? tp("saving") : t("coverSave")}
          </DialogButton>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <div
          {...gestures}
          role="group"
          tabIndex={ready ? 0 : -1}
          aria-label={t("coverPreview")}
          aria-describedby={errorText ? errorId : undefined}
          onKeyDown={onPreviewKey}
          className="relative aspect-video w-full touch-none select-none overflow-hidden rounded-2xl outline-none focus-visible:ring-2"
          style={{ background: "var(--panel-muted)", cursor: ready ? "grab" : "default", ["--tw-ring-color" as string]: "var(--primary)" }}
          data-testid="programme-cover-preview"
        >
          <canvas ref={canvasRef} width={PREVIEW.width} height={PREVIEW.height} className="block h-full w-full" aria-hidden="true" />
          {!ready && !loadError ? (
            <span className="absolute inset-0 grid place-items-center text-sm" style={{ color: "var(--dim)" }}>{tp("loading")}</span>
          ) : null}
        </div>
        {errorText ? (
          <ErrorNotice variant="field">
            <span id={errorId}>{errorText}</span>
          </ErrorNotice>
        ) : null}

        <div className="grid gap-3 sm:grid-cols-2">
          <Range
            id={zoomId}
            label={t("coverZoom")}
            value={edit.zoom}
            min={1}
            max={zoomMax}
            step={0.01}
            disabled={!ready || zoomMax <= 1}
            valueText={`${Math.round(edit.zoom * 100)}%`}
            onChange={(value) => update((size, current) => zoomTo(size, current, value))}
          />
          <Range
            id={brightnessId}
            label={t("coverBrightness")}
            value={edit.brightness}
            min={COVER_MIN_BRIGHTNESS}
            max={COVER_MAX_BRIGHTNESS}
            step={0.01}
            disabled={!ready}
            valueText={`${Math.round(edit.brightness * 100)}%`}
            onChange={(value) => update((size, current) => brightnessTo(size, current, value))}
          />
        </div>
        <div className="flex flex-wrap gap-2">
          <CoverButton onClick={() => update((size, current) => rotateClockwise(size, current))} testId="programme-cover-rotate">
            <span aria-hidden="true">↻ </span>
            {t("coverRotate")}
          </CoverButton>
          <CoverButton onClick={() => update((size) => fromApiEdit(size, null))}>{t("coverReset")}</CoverButton>
        </div>
      </div>
    </Dialog>
  );
}

function Range({
  id,
  label,
  value,
  min,
  max,
  step,
  disabled,
  valueText,
  onChange,
}: {
  id: string;
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  disabled: boolean;
  valueText: string;
  onChange: (value: number) => void;
}) {
  return (
    <div className="flex flex-col gap-1">
      <span className="flex items-baseline justify-between gap-2 text-sm font-semibold" style={{ color: disabled ? "var(--dim)" : "var(--text)" }}>
        <label htmlFor={id}>{label}</label>
        <span className="text-xs tabular-nums" style={{ color: "var(--muted)" }}>{valueText}</span>
      </span>
      <input
        id={id}
        type="range"
        className="block h-11 w-full disabled:cursor-not-allowed"
        style={{ accentColor: "var(--primary)", opacity: disabled ? 0.5 : 1 }}
        value={value}
        min={min}
        max={max}
        step={step}
        disabled={disabled}
        aria-valuetext={valueText}
        onChange={(event) => onChange(Number(event.target.value))}
      />
    </div>
  );
}

/** Drag to move the photo, pinch to zoom; deltas in window widths/heights. */
function useDragGestures({ onPan, onZoom }: { onPan: (dx: number, dy: number) => void; onZoom: (factor: number) => void }) {
  const pointers = useRef(new Map<number, { x: number; y: number }>());
  const pinch = useRef<number | null>(null);
  const distance = () => {
    const [a, b] = [...pointers.current.values()];
    return a && b ? Math.hypot(a.x - b.x, a.y - b.y) : null;
  };
  const end = (event: ReactPointerEvent<HTMLElement>) => {
    pointers.current.delete(event.pointerId);
    pinch.current = distance();
  };
  return {
    onPointerDown(event: ReactPointerEvent<HTMLElement>) {
      event.currentTarget.setPointerCapture?.(event.pointerId);
      pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
      pinch.current = distance();
    },
    onPointerMove(event: ReactPointerEvent<HTMLElement>) {
      const previous = pointers.current.get(event.pointerId);
      if (!previous) return;
      pointers.current.set(event.pointerId, { x: event.clientX, y: event.clientY });
      if (pointers.current.size >= 2) {
        const next = distance();
        if (next && pinch.current) onZoom(next / pinch.current);
        pinch.current = next;
        return;
      }
      const width = event.currentTarget.clientWidth || 1;
      const height = event.currentTarget.clientHeight || 1;
      onPan((event.clientX - previous.x) / width, (event.clientY - previous.y) / height);
    },
    onPointerUp: end,
    onPointerCancel: end,
  };
}
