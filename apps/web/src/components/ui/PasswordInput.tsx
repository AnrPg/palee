"use client";

import { useState, type CSSProperties, type InputHTMLAttributes } from "react";
import { useTranslations } from "next-intl";

/**
 * Show / hide what was typed in a password or secret field (2026-11-22).
 *
 * Every masked field of the app goes through `PasswordInput`, or, where the
 * field draws its own frame (auth/AuthField), through `PasswordRevealButton`
 * plus `usePasswordReveal`. The guard test `password-input-guard.test.ts`
 * keeps raw `type="password"` inputs out of the screens.
 */

/** Which words the button uses: a login password, or an API key / token / secret. */
export type RevealKind = "password" | "key";

export function usePasswordReveal() {
  const [shown, setShown] = useState(false);
  return {
    shown,
    type: shown ? "text" : "password",
    toggle: () => setShown((current) => !current),
  } as const;
}

const LABEL_KEYS = {
  password: { show: "showPassword", hide: "hidePassword" },
  key: { show: "showKey", hide: "hideKey" },
} as const;

type RevealButtonProps = {
  shown: boolean;
  onToggle: () => void;
  /** The id of the input it reveals. */
  controls?: string;
  kind?: RevealKind;
  disabled?: boolean;
  className?: string;
};

/** The eye button. Keeps the focus (and a phone's keyboard) in the input. */
export function PasswordRevealButton({
  shown,
  onToggle,
  controls,
  kind = "password",
  disabled,
  className,
}: RevealButtonProps) {
  const t = useTranslations("Common");
  const keys = LABEL_KEYS[kind];
  return (
    <button
      type="button"
      data-password-reveal
      aria-label={t(shown ? keys.hide : keys.show)}
      aria-controls={controls}
      disabled={disabled}
      onPointerDown={(event) => event.preventDefault()}
      onClick={onToggle}
      className={`inline-flex shrink-0 items-center justify-center rounded-lg disabled:opacity-50 ${className ?? "h-11 w-11"}`}
      style={{ color: "var(--dim)", background: "transparent" }}
    >
      {shown ? <EyeOffIcon /> : <EyeIcon />}
    </button>
  );
}

type PasswordInputProps = Omit<
  InputHTMLAttributes<HTMLInputElement>,
  "type"
> & {
  kind?: RevealKind;
  /** Classes of the frame that holds the input and the button (margins, flex sizing). */
  containerClassName?: string;
};

/** Drop-in for `<input type="password">` with an eye button at the end of the field. */
export function PasswordInput({
  kind = "password",
  containerClassName,
  style,
  id,
  disabled,
  ...props
}: PasswordInputProps) {
  const reveal = usePasswordReveal();
  const inputStyle: CSSProperties = { ...style, paddingInlineEnd: "2.75rem" };
  return (
    <span className={`relative block ${containerClassName ?? "w-full"}`}>
      <input
        {...props}
        id={id}
        disabled={disabled}
        type={reveal.type}
        style={inputStyle}
      />
      <PasswordRevealButton
        shown={reveal.shown}
        onToggle={reveal.toggle}
        controls={id}
        kind={kind}
        disabled={disabled}
        className="absolute inset-y-0 end-0 my-auto h-11 max-h-full w-11"
      />
    </span>
  );
}

function EyeIcon() {
  return (
    <svg
      width={18}
      height={18}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7S2 12 2 12Z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}

function EyeOffIcon() {
  return (
    <svg
      width={18}
      height={18}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={1.8}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      <path d="M10.6 5.1A10.6 10.6 0 0 1 12 5c6.4 0 10 7 10 7a17.6 17.6 0 0 1-3.2 4.2" />
      <path d="M6.6 6.6C3.7 8.4 2 12 2 12s3.6 7 10 7a9.8 9.8 0 0 0 5.4-1.6" />
      <path d="M9.9 9.9a3 3 0 0 0 4.2 4.2" />
      <path d="m3 3 18 18" />
    </svg>
  );
}

/** A field that is masked (with the eye button) only when it holds a secret; otherwise a plain text input. */
export function MaskableInput({
  masked,
  kind,
  containerClassName,
  type = "text",
  ...props
}: PasswordInputProps & {
  masked: boolean;
  /** The type while unmasked. */ type?: "text" | "email" | "url";
}) {
  if (masked)
    return (
      <PasswordInput
        {...props}
        kind={kind}
        containerClassName={containerClassName}
      />
    );
  return <input {...props} type={type} />;
}
