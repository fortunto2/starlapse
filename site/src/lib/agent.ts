/**
 * The machine-facing description of starlapse.app: agents.txt, the A2A card, the ARD manifest, the
 * RFC 9727 API catalog and the MCP server card. Generators: superduper-site-kit/agent. One file so
 * the cards cannot disagree.
 *
 * What is true here, and so what is published: a read-only MCP server (worker/index.ts) with two
 * tools, get_app_info and get_privacy, answered from the product registry at build time. What is
 * not: accounts, OAuth, payments, any write, and anything from the app's optional sky dataset.
 * The camera app itself runs on the iPhone; an agent cannot call it.
 */
import { a2aSkill, agentCard as kitCard, agentPolicyText as kitPolicy, apiCatalog as kitApi, ardCoreEntries, ardManifest as kitArd, mcpServerCard as kitMcpCard } from 'superduper-site-kit/agent';
import { COMPANY } from 'superduper-site-kit/company';

export const DOMAIN = 'starlapse.app';
export const BASE = `https://${DOMAIN}`;
export const EMAIL = 'info@superduperai.co';

export const URLS = {
  llms: `${BASE}/llms.txt`,
  llmsFull: `${BASE}/llms-full.txt`,
  sitemap: `${BASE}/sitemap-index.xml`,
  mcp: `${BASE}/mcp`,
  mcpCard: `${BASE}/.well-known/mcp/server-card.json`,
  agentCard: `${BASE}/.well-known/agent-card.json`,
  apiCatalog: `${BASE}/.well-known/api-catalog`,
  ard: `${BASE}/.well-known/ard.json`,
  agentsTxt: `${BASE}/agents.txt`,
  index: `${BASE}/agent-index.json`,
  privacy: `${BASE}/privacy/`,
} as const;

export const MCP_TOOLS = [
  {
    id: 'get_app_info',
    name: 'About Starlapse',
    description:
      'What Starlapse is: a long-exposure night-sky camera for iPhone that stacks one-second frames into one long exposure. Its features, price, ' +
      'languages, the honest limits (fixed aperture, one-second frame cap, no background capture) and where to get it. Read-only.',
    tags: ['app', 'astrophotography', 'iphone'],
    examples: ['what does Starlapse do', 'how much does Starlapse Pro cost', 'which languages does Starlapse support'],
    out: 'text/markdown',
  },
  {
    id: 'get_privacy',
    name: 'Starlapse privacy facts',
    description:
      'What the app collects and what stays on the phone: the policy summary, data kept on the device, the network calls, the permissions and why, ' +
      'and how deletion works. The same text as the privacy page. Read-only; it describes the policy and returns no user data.',
    tags: ['privacy', 'policy'],
    examples: ['does Starlapse upload my photos', 'what permissions does Starlapse need'],
    out: 'text/markdown',
  },
] as const;

export function agentPolicyText(): string {
  return kitPolicy({
    domain: DOMAIN,
    about: [
      'Starlapse: long-exposure night-sky camera for iPhone. Free on the App Store; Starlapse Pro is a',
      'one-time purchase. This site is a static landing page, a privacy policy and a support page.',
      'Nothing here needs an account. robots.txt carries the same policy as a Content-Signal;',
      'this file says it in words.',
    ],
    may: [
      'read, index and link to every page                      (search=yes)',
      'quote it when answering someone, with a link to the page (ai-input=yes)',
      `call the MCP server at ${URLS.mcp}, no key needed (tools: get_app_info, get_privacy);\nread-only, 120 requests a minute`,
    ],
    mustNot: ['fold the content into a training corpus                  (ai-train=no)'],
    notOffered: [
      `accounts, sign-in or OAuth: nothing on ${DOMAIN} is protected`,
      'taking photos or running the app for a person: Starlapse runs on the iPhone, there is no endpoint for it',
      'access to the optional sky dataset contributed from the app, payments through this site, or write access of any kind',
    ],
    start: [
      ['Site map for models', URLS.llms],
      ['Sitemap', URLS.sitemap],
      ['MCP server', URLS.mcp],
      ['MCP server card', URLS.mcpCard],
      ['Agent card', URLS.agentCard],
      ['Resource catalogue', URLS.ard],
      ['API catalogue', URLS.apiCatalog],
      ['Privacy policy', URLS.privacy],
      ['Markdown', 'send "Accept: text/markdown" to the home page, which answers with /llms.txt'],
    ],
    contact: EMAIL,
  });
}

export function agentCard() {
  return kitCard({
    domain: DOMAIN,
    description:
      'Starlapse: long-exposure night-sky camera for iPhone, with a landing page, privacy policy and support page. Read-only: ' +
      'get the app facts and the privacy facts. Not a conversational agent and no A2A task endpoint: the callable interface is an MCP ' +
      `server (streamable HTTP, stateless, no authentication), described at ${URLS.mcpCard}.`,
    mcpUrl: URLS.mcp,
    provider: { organization: COMPANY.us.name, url: BASE },
    iconUrl: `${BASE}/icon-512.png`,
    documentationUrl: URLS.llms,
    skills: MCP_TOOLS.map((t) => a2aSkill({ id: t.id, name: t.name, description: t.description, tags: [...t.tags], examples: [...t.examples], out: t.out })),
  });
}

export function mcpServerCard() {
  return kitMcpCard({
    domain: DOMAIN,
    title: 'Starlapse: night-sky camera for iPhone',
    description: 'Facts about the Starlapse app (features, price, limits) and its privacy policy. Read-only; no key, nothing stored.',
    websiteUrl: BASE,
    mcpUrl: URLS.mcp,
    tools: MCP_TOOLS.map((t) => ({ name: t.id, description: t.description })),
  });
}

export function apiCatalog() {
  return kitApi(URLS.apiCatalog, [
    {
      href: URLS.mcp,
      'service-desc': [{ href: URLS.mcpCard, type: 'application/json' }],
      'service-doc': [{ href: URLS.agentsTxt, type: 'text/plain' }, { href: URLS.llms, type: 'text/plain' }],
    },
  ]);
}

export function ardManifest() {
  return kitArd(DOMAIN, ardCoreEntries({
    domain: DOMAIN, mcpCardUrl: URLS.mcpCard, agentCardUrl: URLS.agentCard,
    mcpDescription: 'Facts about the Starlapse night-sky camera app and its privacy policy. Streamable HTTP, no authentication, read-only.',
    mcpQueries: ['what is Starlapse', 'does Starlapse upload photos', 'how to photograph stars with an iPhone app'],
    capabilities: ['read'], tags: ['mcp', 'iphone', 'read-only'],
    cardDescription: 'What an agent can get here and through which interface (MCP; there is no A2A task endpoint).',
    cardQueries: ['what can an agent do on starlapse.app'],
  }));
}
