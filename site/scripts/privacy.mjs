// The policy has one source, PRIVACY.md at the repo root (App Store Connect links the
// GitHub Pages copy of it too). Copied here before every build so the two never drift.
import { copyFileSync } from 'node:fs';
copyFileSync(new URL('../../PRIVACY.md', import.meta.url), new URL('../src/privacy.md', import.meta.url));
