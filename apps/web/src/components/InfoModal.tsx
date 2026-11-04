"use client";

import {useUiTranslations} from "@/i18n/ui";
import { Dialog } from "@/components/ui/Dialog";
import { HELP_ICON_CLASS, HELP_ICON_STYLE } from "@/components/HelpTooltip";

type InfoModalProps = {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
};

export function InfoModal({ title, onClose, children }: InfoModalProps) {
  return (
    <Dialog onClose={onClose} title={title} size="md" variant="center">
      <div className="space-y-3 text-sm leading-6" style={{ color: "var(--muted)" }}>
        {children}
      </div>
    </Dialog>
  );
}

type HelpIconProps = {
  tooltip: string;
  onClick: () => void;
};

export function HelpIcon({ tooltip, onClick }: HelpIconProps) {
  const i18n = useUiTranslations();
  return (
    <button
      className={`hit-area ${HELP_ICON_CLASS}`}
      style={HELP_ICON_STYLE}
      title={tooltip}
      onClick={onClick}
      type="button"
      aria-label={i18n("infoWithText", { text: tooltip })}
    >
      ?
    </button>
  );
}
