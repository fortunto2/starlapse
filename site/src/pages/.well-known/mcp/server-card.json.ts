/** /.well-known/mcp/server-card.json: how an agent finds the MCP server at /mcp. */
import type { APIRoute } from 'astro';
import { json } from 'superduper-site-kit/agent';
import { mcpServerCard } from '../../../lib/agent';

export const GET: APIRoute = () => json(mcpServerCard());
