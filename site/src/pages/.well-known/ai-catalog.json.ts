/** /.well-known/ai-catalog.json: the ARD manifest at its predecessor path, identical to ard.json. */
import type { APIRoute } from 'astro';
import { json } from 'superduper-site-kit/agent';
import { ardManifest } from '../../lib/agent';

export const GET: APIRoute = () => json(ardManifest());
