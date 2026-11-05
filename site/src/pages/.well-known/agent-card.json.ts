/** /.well-known/agent-card.json: A2A-shaped card whose transport is the MCP server. */
import type { APIRoute } from 'astro';
import { json } from 'superduper-site-kit/agent';
import { agentCard } from '../../lib/agent';

export const GET: APIRoute = () => json(agentCard());
