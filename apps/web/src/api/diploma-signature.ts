import { apiRequest } from "@/api/client";

/**
 * ADR-377 addendum (option Γ): the signed-in coach's own signature for
 * diplomas. Only its owner reads it; the image is drawn inside diploma PDFs
 * and never sent to anyone else.
 */
export type DiplomaSignature = {
  id: string;
  content_type: string;
  byte_size: number;
  width: number;
  height: number;
  updated_at: string;
};

export type DiplomaSignatureLimits = {
  max_bytes: number;
  content_types: string[];
  min_width: number;
  min_height: number;
  max_width: number;
  max_height: number;
};

export type DiplomaSignatureState = {
  eligible: boolean;
  signature: DiplomaSignature | null;
  limits: DiplomaSignatureLimits;
};

export const DEFAULT_SIGNATURE_LIMITS: DiplomaSignatureLimits = {
  max_bytes: 512 * 1024,
  content_types: ["image/jpeg", "image/png"],
  min_width: 60,
  min_height: 20,
  max_width: 1600,
  max_height: 800,
};

function signatureOrNull(value: unknown): DiplomaSignature | null {
  if (!value || typeof value !== "object") return null;
  const signature = value as Partial<DiplomaSignature>;
  return typeof signature.id === "string" ? (signature as DiplomaSignature) : null;
}

/** Normalises the answer: anything malformed reads as "not a coach, no signature". */
export function normalizeSignatureState(value: unknown): DiplomaSignatureState {
  const body = value && typeof value === "object" ? (value as Record<string, unknown>) : {};
  const limits = body.limits && typeof body.limits === "object" ? (body.limits as Partial<DiplomaSignatureLimits>) : {};
  return {
    eligible: body.eligible === true,
    signature: signatureOrNull(body.signature),
    limits: {
      ...DEFAULT_SIGNATURE_LIMITS,
      ...Object.fromEntries(Object.entries(limits).filter(([, v]) => v !== undefined && v !== null)),
    } as DiplomaSignatureLimits,
  };
}

export async function getDiplomaSignature(token: string) {
  return normalizeSignatureState(await apiRequest<unknown>("/me/diploma-signature", { token }));
}

export async function uploadDiplomaSignature(token: string, imageBase64: string) {
  const result = await apiRequest<{ signature?: unknown }>("/me/diploma-signature", {
    method: "POST",
    token,
    body: { image_base64: imageBase64 },
  });
  return signatureOrNull(result?.signature);
}

export async function getDiplomaSignatureImage(token: string) {
  return apiRequest<Blob>("/me/diploma-signature/image", { token, responseType: "blob" });
}

export async function deleteDiplomaSignature(token: string) {
  await apiRequest<unknown>("/me/diploma-signature", { method: "DELETE", token });
}
