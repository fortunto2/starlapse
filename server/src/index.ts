import { Hono } from "hono";
import { isJpeg, MAX_PHOTO_BYTES, Observation, photoKey, row } from "./observation";

type Env = { DB: D1Database; PHOTOS: R2Bucket };

const app = new Hono<{ Bindings: Env }>();

app.get("/", (c) => c.text("Starlapse sky dataset. Contributions only; nothing is served back.\n"));

/**
 * One contribution: multipart with `observation` (JSON) and an optional `photo` (JPEG).
 * Idempotent on the observation id, so a retry after a dropped connection is harmless.
 */
app.post("/v1/observations", async (c) => {
  const form = await c.req.formData().catch(() => null);
  const raw = form?.get("observation");
  if (typeof raw !== "string") return c.json({ error: "observation missing" }, 400);
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    // A 400, not a 500: the phone retries 5xx, and a file that can never parse would
    // otherwise block its queue for good.
    return c.json({ error: "observation is not JSON" }, 400);
  }
  const parsed = Observation.safeParse(json);
  if (!parsed.success) return c.json({ error: "invalid", issues: parsed.error.issues.slice(0, 5) }, 400);
  const observation = parsed.data;

  let key: string | null = null;
  const photo: unknown = form?.get("photo");
  if (photo instanceof File) {
    if (photo.size > MAX_PHOTO_BYTES) return c.json({ error: "photo too large" }, 413);
    const bytes = new Uint8Array(await photo.arrayBuffer());
    if (!isJpeg(bytes)) return c.json({ error: "photo must be a JPEG" }, 415);
    key = photoKey(observation);
    await c.env.PHOTOS.put(key, bytes, { httpMetadata: { contentType: "image/jpeg" } });
  }

  const values = row(observation, new Date(), key);
  await c.env.DB.prepare(
    `INSERT OR REPLACE INTO observations VALUES (${values.map(() => "?").join(", ")})`,
  )
    .bind(...values)
    .run();
  return c.json({ stored: observation.id, photo: key !== null }, 201);
});

/**
 * Everything from one phone, rows and photos. The contributor id is a random UUID that only
 * that phone holds, which is what makes it enough to ask.
 */
app.delete("/v1/contributors/:id", async (c) => {
  const id = c.req.param("id");
  if (!/^[0-9a-f-]{36}$/i.test(id)) return c.json({ error: "invalid id" }, 400);
  let cursor: string | undefined;
  let removed = 0;
  do {
    const page = await c.env.PHOTOS.list({ prefix: `photos/${id}/`, cursor });
    if (page.objects.length > 0) await c.env.PHOTOS.delete(page.objects.map((o) => o.key));
    removed += page.objects.length;
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  const result = await c.env.DB.prepare("DELETE FROM observations WHERE contributor = ?").bind(id).run();
  return c.json({ rows: result.meta.changes, photos: removed });
});

export default app;
