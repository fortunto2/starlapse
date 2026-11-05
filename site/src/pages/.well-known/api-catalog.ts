/** /.well-known/api-catalog: RFC 9727. public/_headers sets application/linkset+json on this extensionless file. */
import type { APIRoute } from 'astro';
import { LINKSET_TYPE, json } from 'superduper-site-kit/agent';
import { apiCatalog } from '../../lib/agent';

export const GET: APIRoute = () => json(apiCatalog(), LINKSET_TYPE);
