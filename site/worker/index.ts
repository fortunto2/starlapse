/**
 * The Worker in front of the static assets: markdown for agents on the home page and the MCP
 * endpoint. wrangler.jsonc sends only "/" and "/mcp" here (run_worker_first); every other path is
 * served by the asset server without invoking this code. Logic: superduper-site-kit/agent-worker.
 *
 * POST /mcp: a read-only MCP server, two tools, no user data, nothing stored. Both read the
 * build's /agent-index.json through the ASSETS binding.
 */
import { agentWorker } from 'superduper-site-kit/agent-worker';
import { createMcpHandler, loadJson, type McpTool } from 'superduper-site-kit/agent-mcp';

type Env = { ASSETS: { fetch(r: Request): Promise<Response> } };
type Index = { info: string; privacy: string };

const READ_ONLY = { readOnlyHint: true, openWorldHint: false };
const noArgs = { type: 'object', properties: {} };

const tools: McpTool<Env>[] = [
  {
    name: 'get_app_info',
    title: 'About Starlapse',
    description: 'What Starlapse is (a long-exposure night-sky camera for iPhone), its features, price, languages, honest limits and where to get it. Markdown.',
    inputSchema: noArgs,
    annotations: READ_ONLY,
    async run(_args, { env, origin }) { return { text: (await loadJson<Index>(env, origin, '/agent-index.json')).info }; },
  },
  {
    name: 'get_privacy',
    title: 'Starlapse privacy facts',
    description: 'What the app collects, what stays on the phone, its network calls, permissions and how deletion works. Describes the policy; returns no user data. Markdown.',
    inputSchema: noArgs,
    annotations: READ_ONLY,
    async run(_args, { env, origin }) { return { text: (await loadJson<Index>(env, origin, '/agent-index.json')).privacy }; },
  },
];

export default agentWorker<Env>({
  negotiation: { mode: 'rewrite', home: '/llms.txt', twinPath: () => null },
  mcp: createMcpHandler<Env>({
    server: { name: 'starlapse.app', title: 'Starlapse: night-sky camera for iPhone', version: '1.0.0' },
    instructions: 'Facts about the Starlapse iPhone app. Read-only: get_app_info for what it does and costs, get_privacy for what it collects. Public content, may be quoted with a link back.',
    tools,
    docsUrl: 'https://starlapse.app/llms.txt',
  }),
});
