import type { OrganizationBranding, OrganizationLogoApi } from "@/api/organization-branding";

// ADR-121: client-side mirror of the server's logo policy. The server
// re-validates the stored bytes (magic bytes + size), so these checks only
// spare the user a pointless upload. SVG is deliberately not accepted.
export const TENANT_LOGO_CONTENT_TYPES = ["image/png", "image/jpeg", "image/webp"] as const;
export const TENANT_LOGO_MAX_BYTES = 2 * 1024 * 1024;
export const TENANT_LOGO_ACCEPT = TENANT_LOGO_CONTENT_TYPES.join(",");

export type TenantLogoFileProblem = "empty" | "unsupportedType" | "tooLarge";

export function validateTenantLogoFile(file: { type: string; size: number }): TenantLogoFileProblem | null {
  if (!(TENANT_LOGO_CONTENT_TYPES as readonly string[]).includes(file.type)) return "unsupportedType";
  if (file.size <= 0) return "empty";
  if (file.size > TENANT_LOGO_MAX_BYTES) return "tooLarge";
  return null;
}

export class TenantLogoUploadError extends Error {
  constructor(public readonly reason: TenantLogoFileProblem | "storageRejected") {
    super(reason);
    this.name = "TenantLogoUploadError";
  }
}

/** Turns a WebP into a PNG (transparency kept); null when the browser cannot. */
export type ToPng = (file: Blob) => Promise<Blob | null>;

async function canvasToPng(file: Blob): Promise<Blob | null> {
  if (typeof createImageBitmap !== "function" || typeof document === "undefined") return null;
  try {
    const bitmap = await createImageBitmap(file);
    try {
      const canvas = document.createElement("canvas");
      canvas.width = bitmap.width;
      canvas.height = bitmap.height;
      const context = canvas.getContext("2d");
      if (!context) return null;
      context.drawImage(bitmap, 0, 0);
      return await new Promise((resolve) => canvas.toBlob((blob) => resolve(blob), "image/png"));
    } finally {
      bitmap.close();
    }
  } catch {
    return null;
  }
}

/**
 * A WebP logo is stored as a PNG (ADR-377 amendment): a diploma PDF cannot
 * hold WebP and the server has no image library. When the browser cannot
 * convert it, or the PNG would be over the limit, the WebP goes as it is
 * (the diploma then shows only the box name).
 */
export async function logoForUpload(file: File, toPng: ToPng = canvasToPng): Promise<File> {
  if (file.type !== "image/webp") return file;
  const png = await toPng(file);
  if (!png || png.type !== "image/png" || png.size <= 0 || png.size > TENANT_LOGO_MAX_BYTES) return file;
  const name = file.name.replace(/\.webp$/i, "") || "logo";
  return new File([png], `${name}.png`, { type: "image/png" });
}

type PutObject = (url: string, init: { method: "PUT"; body: Blob; headers: Record<string, string> }) => Promise<{ ok: boolean }>;

/**
 * Request a presigned upload, PUT the file straight to object storage, then
 * ask the API to verify and adopt it. Rejects with `TenantLogoUploadError` for
 * client-side problems or a failed storage PUT; API errors propagate as-is.
 */
export async function uploadTenantLogo(
  picked: File,
  api: Pick<OrganizationLogoApi, "requestUpload" | "finalize">,
  putObject: PutObject = (url, init) => fetch(url, init),
  toPng: ToPng = canvasToPng,
): Promise<OrganizationBranding> {
  const problem = validateTenantLogoFile(picked);
  if (problem) throw new TenantLogoUploadError(problem);
  const file = await logoForUpload(picked, toPng);

  const upload = await api.requestUpload(file);
  const response = await putObject(upload.upload_url, {
    method: "PUT",
    body: file,
    headers: upload.required_headers,
  });
  if (!response.ok) throw new TenantLogoUploadError("storageRejected");

  return api.finalize(upload.key);
}
