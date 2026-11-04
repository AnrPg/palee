import { describe, expect, it, vi } from "vitest";

import type { OrganizationBranding } from "@/api/organization-branding";
import {
  TENANT_LOGO_MAX_BYTES,
  TenantLogoUploadError,
  logoForUpload,
  uploadTenantLogo,
  validateTenantLogoFile,
} from "@/lib/tenant-logo-upload";

const branding: OrganizationBranding = {
  organization_id: "org-1",
  brand_name: "Gym",
  brand_logo_url: "https://media.test/organizations/org-1/branding/logo/a.png",
  brand_logo_uploaded: true,
  brand_primary_color: null,
};

function logoFile(type = "image/png", size = 1024) {
  return new File([new Uint8Array(size)], "logo", { type });
}

describe("validateTenantLogoFile", () => {
  it("accepts PNG, JPEG and WebP up to 2 MiB", () => {
    for (const type of ["image/png", "image/jpeg", "image/webp"]) {
      expect(validateTenantLogoFile({ type, size: TENANT_LOGO_MAX_BYTES })).toBeNull();
    }
  });

  it("rejects SVG and other types", () => {
    expect(validateTenantLogoFile({ type: "image/svg+xml", size: 10 })).toBe("unsupportedType");
    expect(validateTenantLogoFile({ type: "image/gif", size: 10 })).toBe("unsupportedType");
    expect(validateTenantLogoFile({ type: "", size: 10 })).toBe("unsupportedType");
  });

  it("rejects empty and oversized files", () => {
    expect(validateTenantLogoFile({ type: "image/png", size: 0 })).toBe("empty");
    expect(validateTenantLogoFile({ type: "image/png", size: TENANT_LOGO_MAX_BYTES + 1 })).toBe("tooLarge");
  });
});

describe("uploadTenantLogo", () => {
  it("requests, PUTs with the required headers, then finalizes the key", async () => {
    const api = {
      requestUpload: vi.fn().mockResolvedValue({
        upload_url: "https://media.test/upload",
        key: "organizations/org-1/branding/logo/a.png",
        required_headers: { "content-type": "image/png" },
        expires_in: 900,
        max_bytes: TENANT_LOGO_MAX_BYTES,
      }),
      finalize: vi.fn().mockResolvedValue(branding),
    };
    const putObject = vi.fn().mockResolvedValue({ ok: true });
    const file = logoFile();

    await expect(uploadTenantLogo(file, api, putObject)).resolves.toEqual(branding);

    expect(api.requestUpload).toHaveBeenCalledWith(file);
    expect(putObject).toHaveBeenCalledWith("https://media.test/upload", {
      method: "PUT",
      body: file,
      headers: { "content-type": "image/png" },
    });
    expect(api.finalize).toHaveBeenCalledWith("organizations/org-1/branding/logo/a.png");
  });

  it("never contacts the API for an invalid file", async () => {
    const api = { requestUpload: vi.fn(), finalize: vi.fn() };

    await expect(uploadTenantLogo(logoFile("image/svg+xml"), api)).rejects.toEqual(
      new TenantLogoUploadError("unsupportedType"),
    );
    expect(api.requestUpload).not.toHaveBeenCalled();
  });

  it("does not finalize when storage rejects the PUT", async () => {
    const api = {
      requestUpload: vi.fn().mockResolvedValue({
        upload_url: "https://media.test/upload",
        key: "k",
        required_headers: {},
        expires_in: 900,
        max_bytes: TENANT_LOGO_MAX_BYTES,
      }),
      finalize: vi.fn(),
    };

    await expect(
      uploadTenantLogo(logoFile(), api, vi.fn().mockResolvedValue({ ok: false })),
    ).rejects.toMatchObject({ reason: "storageRejected" });
    expect(api.finalize).not.toHaveBeenCalled();
  });
});

describe("logoForUpload (ADR-377 amendment: diplomas cannot hold WebP)", () => {
  it("turns a WebP into a PNG and leaves PNG and JPEG alone", async () => {
    const toPng = vi.fn().mockResolvedValue(new Blob([new Uint8Array(8)], { type: "image/png" }));
    const png = await logoForUpload(new File([new Uint8Array(4)], "brand.webp", { type: "image/webp" }), toPng);
    expect(png.type).toBe("image/png");
    expect(png.name).toBe("brand.png");
    const jpeg = logoFile("image/jpeg");
    expect(await logoForUpload(jpeg, toPng)).toBe(jpeg);
    expect(toPng).toHaveBeenCalledTimes(1);
  });

  it("keeps the WebP when the browser cannot convert it or the PNG is too large", async () => {
    const webp = logoFile("image/webp");
    expect(await logoForUpload(webp, vi.fn().mockResolvedValue(null))).toBe(webp);
    const huge = new Blob([new Uint8Array(TENANT_LOGO_MAX_BYTES + 1)], { type: "image/png" });
    expect(await logoForUpload(webp, vi.fn().mockResolvedValue(huge))).toBe(webp);
  });

  it("uploads the converted PNG", async () => {
    const api = {
      requestUpload: vi.fn().mockResolvedValue({ upload_url: "https://media.test/u", key: "k", required_headers: {}, expires_in: 900, max_bytes: 1 }),
      finalize: vi.fn().mockResolvedValue(branding),
    };
    const putObject = vi.fn().mockResolvedValue({ ok: true });
    const toPng = vi.fn().mockResolvedValue(new Blob([new Uint8Array(8)], { type: "image/png" }));
    await uploadTenantLogo(logoFile("image/webp"), api, putObject, toPng);
    expect(api.requestUpload).toHaveBeenCalledWith(expect.objectContaining({ type: "image/png", size: 8 }));
  });
});
