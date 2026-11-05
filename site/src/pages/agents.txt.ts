/** /agents.txt: what an agent may request here. Same text as /.well-known/ai.txt. */
import type { APIRoute } from 'astro';
import { text } from 'superduper-site-kit/agent';
import { agentPolicyText } from '../lib/agent';

export const GET: APIRoute = () => text(agentPolicyText());
