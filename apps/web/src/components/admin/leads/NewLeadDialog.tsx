"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useTranslations } from "next-intl";
import { useState } from "react";

import { fetchAdminUsers } from "@/api/admin-users";
import { createLead, LEADS_KEY, leadKey, STAFF_SOURCES, type StaffSource } from "@/api/leads";
import { SegmentPicker } from "@/components/filters/SegmentPicker";
import { useSession } from "@/components/session-provider";
import { Dialog, DialogButton } from "@/components/ui/Dialog";
import { Select } from "@/components/ui/Select";

import { validateLeadForm, type LeadFormErrors } from "./lead-model";
import { FieldError, FieldLabel, fieldClass, fieldStyle, useLeadErrorText } from "./leads-ui";

/**
 * «Νέος ενδιαφερόμενος» (W2 p1): name, a phone or an email, where they came
 * from and the person's own yes to news and offers. Owner, campaign and
 * their message sit under «Προχωρημένα».
 */
export function NewLeadDialog({ onClose, onCreated }: { onClose: () => void; onCreated: (id: string) => void }) {
  const t = useTranslations("Leads");
  const { tokens, currentUser } = useSession();
  const token = tokens?.access_token ?? null;
  const queryClient = useQueryClient();
  const errorText = useLeadErrorText();
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [email, setEmail] = useState("");
  const [source, setSource] = useState<StaffSource>("walk_in");
  const [marketing, setMarketing] = useState(false);
  const [advanced, setAdvanced] = useState(false);
  const [ownerId, setOwnerId] = useState<string>(currentUser?.id ?? "");
  const [campaign, setCampaign] = useState("");
  const [message, setMessage] = useState("");
  const [errors, setErrors] = useState<LeadFormErrors>({});

  const staff = useQuery({
    queryKey: ["admin", "leads", "staff"],
    enabled: Boolean(token) && advanced,
    queryFn: () => fetchAdminUsers(token!, { limit: 200 }),
    select: (data) => data.users.filter((user) => user.staff),
  });

  const create = useMutation({
    mutationFn: () =>
      createLead(token!, {
        name: name.trim(),
        ...(phone.trim() ? { phone: phone.trim() } : {}),
        ...(email.trim() ? { email: email.trim() } : {}),
        source,
        marketing_consent: marketing,
        ...(ownerId ? { owner_id: ownerId } : {}),
        ...(campaign.trim() ? { campaign: campaign.trim() } : {}),
        ...(message.trim() ? { message: message.trim() } : {}),
      }),
    onSuccess: (detail) => {
      queryClient.setQueryData(leadKey(detail.lead.id), detail);
      void queryClient.invalidateQueries({ queryKey: LEADS_KEY });
      onCreated(detail.lead.id);
    },
  });

  function submit() {
    const next = validateLeadForm({ name, email, phone });
    setErrors(next);
    if (Object.keys(next).length === 0) create.mutate();
  }

  const contactError = errors.contact ? t("field.contactRequired") : null;

  return (
    <Dialog
      onClose={onClose}
      title={t("newLead")}
      size="md"
      dismissible={!create.isPending}
      onSubmit={(event) => {
        event.preventDefault();
        submit();
      }}
      error={create.isError ? errorText(create.error) : null}
      testId="new-lead-dialog"
      footer={
        <>
          <DialogButton tone="ghost" onClick={onClose}>
            {t("cancel")}
          </DialogButton>
          <DialogButton tone="primary" type="submit" disabled={create.isPending} testId="new-lead-save">
            {t("save")}
          </DialogButton>
        </>
      }
    >
      <div className="space-y-4">
        <div>
          <FieldLabel htmlFor="new-lead-name" required>
            {t("name")}
          </FieldLabel>
          <input
            id="new-lead-name"
            value={name}
            maxLength={200}
            autoComplete="off"
            onChange={(event) => setName(event.target.value)}
            aria-invalid={Boolean(errors.name)}
            aria-describedby={errors.name ? "new-lead-name-error" : undefined}
            className={fieldClass}
            style={fieldStyle(Boolean(errors.name))}
          />
          <FieldError id="new-lead-name-error">{errors.name ? t("field.required") : null}</FieldError>
        </div>
        <div className="grid gap-4 sm:grid-cols-2">
          <div>
            <FieldLabel htmlFor="new-lead-phone">{t("phone")}</FieldLabel>
            <input
              id="new-lead-phone"
              type="tel"
              value={phone}
              maxLength={40}
              onChange={(event) => setPhone(event.target.value)}
              aria-invalid={Boolean(errors.contact)}
              aria-describedby={contactError ? "new-lead-contact-error" : undefined}
              className={fieldClass}
              style={fieldStyle(Boolean(errors.contact))}
            />
          </div>
          <div>
            <FieldLabel htmlFor="new-lead-email">{t("emailLabel")}</FieldLabel>
            <input
              id="new-lead-email"
              type="email"
              value={email}
              maxLength={254}
              onChange={(event) => setEmail(event.target.value)}
              aria-invalid={Boolean(errors.contact || errors.email)}
              aria-describedby={errors.email ? "new-lead-email-error" : contactError ? "new-lead-contact-error" : undefined}
              className={fieldClass}
              style={fieldStyle(Boolean(errors.contact || errors.email))}
            />
            <FieldError id="new-lead-email-error">{errors.email ? t("field.emailInvalid") : null}</FieldError>
          </div>
        </div>
        <FieldError id="new-lead-contact-error">{contactError}</FieldError>

        <div>
          <p className="mb-1 text-sm font-semibold" style={{ color: "var(--text-soft)" }}>
            {t("sourceLabel")}
          </p>
          <SegmentPicker<StaffSource>
            ariaLabel={t("sourceLabel")}
            semantics="radiogroup"
            value={source}
            onChange={setSource}
            options={STAFF_SOURCES.map((value) => ({ value, label: t(`source.${value}`) }))}
          />
        </div>

        <label className="flex items-start gap-3 rounded-2xl p-3" style={{ background: "var(--panel-muted)" }}>
          <input type="checkbox" checked={marketing} onChange={(event) => setMarketing(event.target.checked)} className="mt-1 h-4 w-4" />
          <span>
            <span className="block text-sm font-semibold" style={{ color: "var(--text)" }}>
              {t("marketingConsent")}
            </span>
            <span className="block text-xs" style={{ color: "var(--muted)" }}>
              {t("marketingConsentHint")}
            </span>
          </span>
        </label>

        <button
          type="button"
          aria-expanded={advanced}
          onClick={() => setAdvanced((value) => !value)}
          className="text-sm font-semibold"
          style={{ color: "var(--primary)" }}
        >
          {t("advanced")}
        </button>
        {advanced ? (
          <div className="space-y-4">
            <div className="grid gap-4 sm:grid-cols-2">
              <div>
                <FieldLabel htmlFor="new-lead-owner">{t("owner")}</FieldLabel>
                <Select
                  id="new-lead-owner"
                  aria-label={t("owner")}
                  value={ownerId}
                  onValueChange={setOwnerId}
                  className={fieldClass}
                  style={fieldStyle(false)}
                >
                  <option value="">{t("noOwner")}</option>
                  {currentUser && !(staff.data ?? []).some((user) => user.id === currentUser.id) ? (
                    <option value={currentUser.id}>{currentUser.nickname}</option>
                  ) : null}
                  {(staff.data ?? []).map((user) => (
                    <option key={user.id} value={user.id}>
                      {user.nickname}
                    </option>
                  ))}
                </Select>
              </div>
              <div>
                <FieldLabel htmlFor="new-lead-campaign">{t("campaign")}</FieldLabel>
                <input
                  id="new-lead-campaign"
                  value={campaign}
                  maxLength={200}
                  placeholder={t("campaignPlaceholder")}
                  onChange={(event) => setCampaign(event.target.value)}
                  className={fieldClass}
                  style={fieldStyle(false)}
                />
              </div>
            </div>
            <div>
              <FieldLabel htmlFor="new-lead-message">{t("message")}</FieldLabel>
              <textarea
                id="new-lead-message"
                value={message}
                rows={3}
                maxLength={2000}
                onChange={(event) => setMessage(event.target.value)}
                className={fieldClass}
                style={fieldStyle(false)}
              />
            </div>
          </div>
        ) : null}
      </div>
    </Dialog>
  );
}
