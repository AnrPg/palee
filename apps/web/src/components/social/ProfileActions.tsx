"use client";

import Link from "next/link";
import { useState, type FormEvent } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";

import { personKey, updateProfileCard, type PersonProfile, type ProfileCardRequest } from "@/api/social";
import { clientErrorMessage } from "@/components/client/errors";
import { useSession } from "@/components/session-provider";
import { Switch } from "@/components/body/BodyPreferenceSettings";
import { OPTIONAL_PROFILE_TABS, toggleProfileTab, type PersonTab } from "@/components/social/social-model";
import { Dialog } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";
import { ErrorNotice } from "@/components/ui/ErrorNotice";
import { useUiTranslations } from "@/i18n/ui";
import { useSelectedMembershipRole } from "@/lib/membership-role";

/** Instagram-like: short, flat and quiet; the profile's two buttons share one row. */
export const profileButtonClass =
  "inline-flex min-h-8 w-full min-w-0 items-center justify-center truncate rounded-lg px-2.5 text-[13px] font-semibold disabled:opacity-50";
const PROFILE_BUTTON_STYLE = { background: "var(--panel-raised)", color: "var(--text)" } as const;

export const BIO_MAX = 150;
const NO_BOX = "none";

/** ADR-554: change the card (bio, tabs) and refresh your own profile with the answer. */
function useSaveCard(profile: PersonProfile) {
  const { tokens } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (body: ProfileCardRequest) => updateProfileCard(token!, body),
    onSuccess: (card) => {
      queryClient.setQueryData<PersonProfile>(personKey(profile.id), (current) => (current ? { ...current, ...card } : current));
    },
  });
}

/**
 * «Επεξεργασία προφίλ»: «Λίγα λόγια», the box you show under it and your belt
 * or level there; name, @handle and photo stay in Ρυθμίσεις, one tap away.
 */
export function EditProfileButton({ profile }: { profile: PersonProfile }) {
  const t = useTranslations("Social");
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" className={`hit-area ${profileButtonClass}`} style={PROFILE_BUTTON_STYLE} onClick={() => setOpen(true)}>
        <span className="truncate @max-[18.75rem]:hidden">{t("editProfile")}</span>
        <span className="hidden truncate @max-[18.75rem]:inline">{t("editProfileShort")}</span>
      </button>
      {open ? <EditProfileDialog profile={profile} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

function EditProfileDialog({ profile, onClose }: { profile: PersonProfile; onClose: () => void }) {
  const t = useTranslations("Social");
  const tUi = useUiTranslations();
  const [bio, setBio] = useState(profile.bio ?? "");
  const { memberships } = useSelectedMembershipRole();
  const boxes = memberships.map((entry) => entry.organization);
  const [boxId, setBoxId] = useState(profile.box_id ?? NO_BOX);
  const [showRank, setShowRank] = useState(profile.show_rank);
  const save = useSaveCard(profile);
  const queryClient = useQueryClient();

  function submit(event?: FormEvent) {
    event?.preventDefault();
    const box = boxId === NO_BOX ? null : boxId;
    const rank = Boolean(box) && showRank;
    const boxChanged = box !== (profile.box_id ?? null) || rank !== profile.show_rank;
    save.mutate(boxChanged ? { bio: bio.trim() || null, box_id: box, show_rank: rank } : { bio: bio.trim() || null }, {
      onSuccess: () => {
        // The box line comes with the profile: read it again.
        if (boxChanged) void queryClient.invalidateQueries({ queryKey: personKey(profile.id), exact: true });
        onClose();
      },
    });
  }

  return (
    <Dialog
      title={t("editProfile")}
      onClose={onClose}
      size="md"
      dismissible={!save.isPending}
      onSubmit={submit}
      testId="edit-profile-dialog"
      footer={
        <button
          type="submit"
          disabled={save.isPending}
          className="min-h-11 rounded-2xl px-5 text-sm font-bold disabled:opacity-50"
          style={{ background: "var(--primary)", color: "var(--primary-contrast)" }}
        >
          {t("save")}
        </button>
      }
    >
      <div className="flex flex-col gap-4">
        <label className="flex flex-col gap-1.5">
          <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("bioLabel")}</span>
          <textarea
            value={bio}
            maxLength={BIO_MAX}
            rows={3}
            onChange={(event) => setBio(event.target.value)}
            placeholder={t("bioPlaceholder")}
            className="w-full resize-none rounded-xl px-3 py-2 text-sm outline-none"
            style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
          />
          <span className="self-end text-xs tabular-nums" style={{ color: "var(--dim)" }}>
            {bio.length}/{BIO_MAX}
          </span>
        </label>
        {boxes.length > 0 ? (
          <div className="flex flex-col gap-1.5">
            <span className="text-sm font-semibold" style={{ color: "var(--text)" }}>{t("boxLabel")}</span>
            <Select
              aria-label={t("boxLabel")}
              value={boxId}
              onValueChange={setBoxId}
              className="w-full rounded-xl px-3 py-2 text-sm outline-none"
              style={{ background: "var(--panel-muted)", border: "1px solid var(--border)", color: "var(--text)" }}
            >
              <option value={NO_BOX}>{t("boxNone")}</option>
              {boxes.map((box) => (
                <option key={box.id} value={box.id}>
                  {box.name}
                </option>
              ))}
            </Select>
            <span className="text-xs" style={{ color: "var(--dim)" }}>{t("boxHint")}</span>
            {boxId !== NO_BOX ? <Switch label={t("showRank")} hint={t("showRankHint")} checked={showRank} onChange={setShowRank} /> : null}
          </div>
        ) : null}
        <Link
          href="/me/settings#personal"
          className="flex min-h-11 items-center justify-between rounded-2xl px-4 text-sm font-semibold"
          style={{ background: "var(--panel)", border: "1px solid var(--border)", color: "var(--text)" }}
        >
          {t("nameAndPhoto")}
          <span aria-hidden="true" style={{ color: "var(--dim)" }}>›</span>
        </Link>
        {save.error ? <ErrorNotice>{clientErrorMessage(save.error, tUi)}</ErrorNotice> : null}
      </div>
    </Dialog>
  );
}

/** «Κοινοποίηση προφίλ»: the phone's share sheet, or the link copied. */
export function ShareProfileButton({ profile }: { profile: PersonProfile }) {
  const t = useTranslations("Social");
  const [copied, setCopied] = useState(false);

  async function share() {
    const url = `${window.location.origin}/people/${profile.id}`;
    if (typeof navigator.share === "function") {
      try {
        await navigator.share({ title: profile.nickname ?? undefined, url });
        return;
      } catch {
        // Closed the share sheet: fall back to copying.
      }
    }
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      setCopied(false);
    }
  }

  return (
    <button type="button" className={`hit-area ${profileButtonClass}`} style={PROFILE_BUTTON_STYLE} onClick={() => void share()}>
      <span role="status" className="truncate">
        {copied ? (
          t("profileLinkCopied")
        ) : (
          <>
            <span className="@max-[18.75rem]:hidden">{t("shareProfile")}</span>
            <span className="hidden @max-[18.75rem]:inline">{t("shareProfileShort")}</span>
          </>
        )}
      </span>
    </button>
  );
}

/**
 * «+ Καρτέλα» (ADR-554, 3C): only on your own profile, at the end of the tab
 * row. Switch PRs or «Διακρίσεις» on and the tab appears, last.
 */
export function AddTabButton({ profile, tabs }: { profile: PersonProfile; tabs: PersonTab[] }) {
  const t = useTranslations("Social");
  const [open, setOpen] = useState(false);
  return (
    <>
      <button
        type="button"
        aria-label={t("addTab")}
        onClick={() => setOpen(true)}
        className="flex min-h-12 w-10 shrink-0 items-center justify-center rounded-xl"
        style={{ color: "var(--dim)" }}
        data-testid="profile-add-tab"
      >
        <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
          <path d="M12 5v14M5 12h14" />
        </svg>
      </button>
      {open ? <AddTabDialog profile={profile} tabs={tabs} onClose={() => setOpen(false)} /> : null}
    </>
  );
}

function AddTabDialog({ profile, tabs, onClose }: { profile: PersonProfile; tabs: PersonTab[]; onClose: () => void }) {
  const t = useTranslations("Social");
  const tUi = useUiTranslations();
  const save = useSaveCard(profile);

  return (
    <Dialog title={t("addTabTitle")} description={t("addTabHint")} onClose={onClose} size="md" testId="add-tab-dialog">
      <div className="flex flex-col gap-1">
        {OPTIONAL_PROFILE_TABS.map((tab) => (
          <Switch
            key={tab}
            label={t(`personTab.${tab}`)}
            hint={t(`addTabHints.${tab}`)}
            checked={tabs.includes(tab)}
            disabled={save.isPending}
            onChange={(on) => save.mutate({ tabs: toggleProfileTab(tabs, tab, on) })}
          />
        ))}
        {save.error ? <ErrorNotice>{clientErrorMessage(save.error, tUi)}</ErrorNotice> : null}
      </div>
    </Dialog>
  );
}
