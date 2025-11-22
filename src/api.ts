// src/api.ts
import { Elysia } from "elysia";
import { mainConverter } from "./converters/main";
import { normalizeFiletype } from "./helpers/normalizeFiletype";
import { uploadsDir, outputDir } from ".";
import { randomUUID } from "crypto";
import { join, extname, basename } from "path";
import { mkdir, writeFile } from "fs/promises";

const API_KEY = process.env.API_KEY;

// Helper to build JSON error responses
function jsonError(status: number, message: string) {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: {
      "content-type": "application/json",
    },
  });
}

export const api = new Elysia({ prefix: "/api" })
  .get("/health", () => ({ ok: true }))
  .post("/convert", async ({ request }) => {
    // Optional API key guard
    if (API_KEY) {
      const provided = request.headers.get("x-api-key");
      if (provided !== API_KEY) {
        return jsonError(401, "unauthorized");
      }
    }

    const contentType = request.headers.get("content-type") ?? "";
    if (!contentType.includes("multipart/form-data")) {
      return jsonError(400, "expected multipart/form-data");
    }

    const form = await request.formData();
    const file = form.get("file");
    const targetRaw = form.get("target_format")?.toString();

    if (!(file instanceof File)) {
      return jsonError(400, "missing file field");
    }
    if (!targetRaw) {
      return jsonError(400, "missing target_format field");
    }

    const targetType = normalizeFiletype(targetRaw);
    if (!targetType) {
      return jsonError(400, "invalid target_format");
    }

    // Build directories for this API use
    const uploadBase = join(uploadsDir, "api");
    const outputBase = join(outputDir, "api");

    await mkdir(uploadBase, { recursive: true });
    await mkdir(outputBase, { recursive: true });

    // Input file name
    const originalExt = extname(file.name); // includes dot
    const baseId = randomUUID();
    const inputName = originalExt ? `${baseId}${originalExt}` : baseId;
    const inputPath = join(uploadBase, inputName);

    // Write uploaded file to disk
    const buf = new Uint8Array(await file.arrayBuffer());
    await writeFile(inputPath, buf);

    // Output path: same base name, new extension
    const baseName = basename(inputName, originalExt);
    const outputName = `${baseName}.${targetType}`;
    const outputPath = join(outputBase, outputName);

    // Input file type (extension without dot)
    const inputType = originalExt.startsWith(".")
      ? originalExt.slice(1)
      : originalExt;

    // Call ConvertX core
    let status: string;
    try {
      status = await mainConverter(inputPath, inputType, targetType, outputPath);
    } catch (err) {
      console.error("Conversion error", err);
      return jsonError(500, "conversion_failed");
    }

    if (status !== "Done") {
      return jsonError(500, `conversion_failed_status_${status}`);
    }

    // Stream the file back
    // Bun.file returns a Blob that Elysia can send directly
    const blob = Bun.file(outputPath);

    // You can add a nicer content type here if you want
    return new Response(blob, {
      headers: {
        "content-type": blob.type || "application/octet-stream",
        "content-disposition": `attachment; filename="${outputName}"`,
      },
    });
  });
