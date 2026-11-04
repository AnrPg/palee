"use client";

import { useRef, type TextareaHTMLAttributes } from "react";

import { useExerciseTextSuggestions } from "@/hooks/useExerciseTextSuggestions";

type Props = Omit<TextareaHTMLAttributes<HTMLTextAreaElement>, "value" | "onChange"> & {
  value: string;
  onValueChange: (text: string) => void;
  organizationId?: string | null;
  /** Classes of the wrapper the suggestions are placed in. */
  wrapperClassName?: string;
};

/**
 * ADR-461: a note's textarea that offers exercise names inline, at the
 * caret, while the words just typed match one (`useExerciseTextSuggestions`).
 */
export function ExerciseSuggestingTextarea({ value, onValueChange, organizationId, wrapperClassName, onKeyDown, onBlur, ...props }: Props) {
  const ref = useRef<HTMLTextAreaElement>(null);
  const { textareaProps, menu } = useExerciseTextSuggestions(ref, value, onValueChange, { organizationId });
  return (
    <div className={`relative ${wrapperClassName ?? ""}`}>
      <textarea
        {...props}
        {...textareaProps}
        ref={ref}
        value={value}
        onChange={(event) => onValueChange(event.target.value)}
        onKeyDown={(event) => {
          textareaProps.onKeyDown?.(event);
          if (!event.defaultPrevented) onKeyDown?.(event);
        }}
        onBlur={(event) => {
          textareaProps.onBlur?.(event);
          onBlur?.(event);
        }}
      />
      {menu}
    </div>
  );
}
