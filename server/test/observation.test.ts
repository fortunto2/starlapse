import { describe, expect, it } from "vitest";
import { coarsen, isJpeg, Observation, photoKey, row } from "../src/observation";

const valid = {
  id: "6f1c1b7e-2c3d-4e5f-8a9b-0c1d2e3f4a5b",
  contributor: "0a1b2c3d-4e5f-4a7b-8c9d-0e1f2a3b4c5d",
  takenAt: "2026-10-21T03:00:00Z",
  kind: "stack",
  latitude: 40.4168,
  longitude: -3.7038,
  sky: {
    skyBrightness: 20.8, uncertainty: 0.05, nakedEyeLimit: 6.1, bortle: 4,
    stackLimit: 9.2, matchedStars: 140, altitude: 45, azimuth: 60,
  },
  camera: { lens: "ultraWide", iso: 3200, shutter: 1, frames: 120, fieldOfView: 106, device: "iPhone18,1" },
  appVersion: "1.1.0",
};

describe("observation", () => {
  it("accepts a stack reading", () => {
    expect(Observation.safeParse(valid).success).toBe(true);
  });

  it("rejects a sky brightness no sky has", () => {
    expect(Observation.safeParse({ ...valid, sky: { ...valid.sky, skyBrightness: 40 } }).success).toBe(false);
  });

  it("stores position at 0.1° whatever the client sent", () => {
    const parsed = Observation.parse(valid);
    const values = row(parsed, new Date("2026-10-21T04:00:00Z"), null);
    expect(values[5]).toBe(40.4);
    expect(values[6]).toBe(-3.7);
    expect(coarsen(-0.04)).toBe(-0);
  });

  it("has one value per column", () => {
    const values = row(Observation.parse(valid), new Date(), "photos/x.jpg");
    expect(values).toHaveLength(19);
  });

  it("knows a JPEG from anything else", () => {
    expect(isJpeg(new Uint8Array([0xff, 0xd8, 0xff, 0xe0]))).toBe(true);
    expect(isJpeg(new TextEncoder().encode("<html>"))).toBe(false);
  });

  it("files photos under their contributor, so deletion is one prefix", () => {
    expect(photoKey(Observation.parse(valid))).toBe(`photos/${valid.contributor}/${valid.id}.jpg`);
  });
});
