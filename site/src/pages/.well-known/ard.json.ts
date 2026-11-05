/** /.well-known/ard.json: Agentic Resource Discovery manifest (current path). */
import type { APIRoute } from 'astro';
import { json } from 'superduper-site-kit/agent';
import { ardManifest } from '../../lib/agent';

export const GET: APIRoute = () => json(ardManifest());
