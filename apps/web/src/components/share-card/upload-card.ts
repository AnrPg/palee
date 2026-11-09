import { completeMediaUpload, requestMediaUpload, type MediaContentType } from "@/api/media";
import { putPresigned } from "@/lib/presigned-upload";

/**
 * ADR-565: puts a drawn share card up as a post photo (the same reserve →
 * PUT → complete path as compose, ADR-157) and returns its media id. The
 * post may be created at once: it shows to others when processing ends.
 */
export async function uploadCardPhoto(token: string, file: File): Promise<string> {
  const upload = await requestMediaUpload(token, {
    purpose: "post_photo",
    content_type: file.type as MediaContentType,
    byte_size: file.size,
  });
  await putPresigned(upload.upload_url, file, upload.required_headers);
  await completeMediaUpload(token, upload.media_id);
  return upload.media_id;
}
