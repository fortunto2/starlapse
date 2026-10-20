import { z } from "zod";

/** What a phone sends with each contribution. Mirrors `Contribution` in the app. */
export const Observation = z.object({
  id: z.uuid(),
  contributor: z.uuid(),
  takenAt: z.iso.datetime(),
  kind: z.enum(["stack", "meteors"]),
  // Rounded on the phone; enforced here so a client bug cannot leak a precise position.
  latitude: z.number().min(-90).max(90),
  longitude: z.number().min(-180).max(180),
  sky: z
    .object({
      skyBrightness: z.number().min(10).max(25),
      uncertainty: z.number().min(0).max(5),
      nakedEyeLimit: z.number().min(-2).max(9),
      bortle: z.number().int().min(1).max(9),
      stackLimit: z.number().min(-5).max(25),
      matchedStars: z.number().int().min(0).max(100_000),
      // Whole degrees, as the phone sends them; see the stars' altitude below.
      altitude: z.number().int().min(-90).max(90),
      azimuth: z.number().int().min(0).max(360),
      meterVersion: z.number().int().min(1).max(1000),
      // The raw material, so every reading can be recomputed when the calibration improves.
      stars: z
        .array(
          z.object({
            magnitude: z.number().min(-2).max(9),
            colorIndex: z.number().min(-1).max(3).optional(),
            flux: z.number(),
            background: z.number(),
            pixelArea: z.number().positive(),
            altitude: z.number().int().min(-90).max(90),
          }),
        )
        .max(100),
    })
    .optional(),
  camera: z.object({
    lens: z.string().max(40),
    iso: z.number().min(0).max(1_000_000),
    shutter: z.number().min(0).max(60),
    frames: z.number().int().min(0).max(1_000_000),
    fieldOfView: z.number().min(1).max(180),
    device: z.string().max(40),
  }),
  meteors: z
    .array(
      z.object({
        date: z.iso.datetime(),
        startAzimuth: z.number(),
        startAltitude: z.number(),
        endAzimuth: z.number(),
        endAltitude: z.number(),
        length: z.number().min(0).max(180),
        shower: z.string().max(8).nullable().optional(),
        flux: z.number(),
      }),
    )
    .max(500)
    .optional(),
  appVersion: z.string().max(20),
});
export type Observation = z.infer<typeof Observation>;

/** ~10 km. The phone rounds already; this makes the promise independent of the client. */
export const coarsen = (degrees: number): number => Math.round(degrees * 10) / 10;

export const MAX_PHOTO_BYTES = 8 * 1024 * 1024;

/** A JPEG starts with FF D8 FF. Nothing else is stored. */
export const isJpeg = (bytes: Uint8Array): boolean =>
  bytes.length > 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;

export const photoKey = (observation: Observation): string =>
  `photos/${observation.contributor}/${observation.id}.jpg`;

export const row = (observation: Observation, receivedAt: Date, photo: string | null) => [
  observation.id,
  observation.contributor,
  receivedAt.toISOString(),
  observation.takenAt,
  observation.kind,
  coarsen(observation.latitude),
  coarsen(observation.longitude),
  observation.sky?.skyBrightness ?? null,
  observation.sky?.uncertainty ?? null,
  observation.sky?.nakedEyeLimit ?? null,
  observation.sky?.bortle ?? null,
  observation.sky?.stackLimit ?? null,
  observation.sky?.matchedStars ?? null,
  observation.sky?.altitude ?? null,
  observation.sky?.azimuth ?? null,
  observation.sky?.meterVersion ?? null,
  observation.sky ? JSON.stringify(observation.sky.stars) : null,
  JSON.stringify(observation.camera),
  observation.meteors ? JSON.stringify(observation.meteors) : null,
  photo,
  observation.appVersion,
];
