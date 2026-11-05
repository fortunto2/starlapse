/**
 * The index the read-only MCP server (worker/index.ts) answers from: the app facts and the privacy
 * facts, rendered from the product registry at build time so they cannot drift from the pages.
 */
import type { APIRoute } from 'astro';
import { product } from 'superduper-site-kit/registry';
import { BASE } from '../lib/agent';

const list = (xs: readonly string[]) => xs.map((x) => `- ${x}`).join('\n');

export const GET: APIRoute = () => {
  const p = product('starlapse');
  const info = [
    `# ${p.name}`, '', p.lead, '',
    `Price: ${p.price}. Status: ${p.store_status}. Languages: ${p.languages.join(', ')}.`, '',
    '## Features', '', p.features.map((f) => `- **${f.title}.** ${f.text}`).join('\n'), '',
    '## Honest limits', '',
    list([
      'iPhone aperture is fixed; the app shows what each lens gives up.',
      'A single frame is about one second; everything longer is stacked.',
      'iOS stops the camera in the background; the app keeps the screen on and dims it.',
      'A tripod is required.',
    ]), '',
    `App Store: ${p.links.app_store}`, `Site: ${BASE}`, `Source: https://github.com/${p.links.github}`,
  ].join('\n');
  const v = p.privacy;
  const privacy = [
    `# ${p.name} privacy (updated ${v.updated})`, '', v.summary, '', `Account: ${v.account}`, '',
    '## Collected by us', '', list(v.collected_by_us), '',
    '## Stays on the device', '', list(v.stays_on_device), '',
    '## Network', '', v.network.map((n) => `- ${n.host}: ${n.what}. When: ${n.when}`).join('\n'), '',
    '## Permissions', '', v.permissions.map((x) => `- ${x.permission}: ${x.why}`).join('\n'), '',
    '## Deletion', '', v.deletion, '', `Full policy: ${BASE}/privacy/`,
  ].join('\n');
  return new Response(JSON.stringify({ info, privacy }), {
    headers: { 'content-type': 'application/json; charset=utf-8', 'access-control-allow-origin': '*', 'cache-control': 'public, max-age=3600' },
  });
};
