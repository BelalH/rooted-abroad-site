const ROLES = new Set(['partner', 'buyer', 'other']);
const EMAIL = /^[^@\s]+@[^@\s.]+\.[^@\s]{2,}$/;

function cors(origin, allowed) {
  const ok = allowed.includes(origin);
  return {
    'Access-Control-Allow-Origin': ok ? origin : allowed[0],
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400',
    Vary: 'Origin',
  };
}

function json(body, status, headers) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const allowed = env.ALLOWED_ORIGINS.split(',').map((s) => s.trim());
    const headers = cors(request.headers.get('Origin') || '', allowed);

    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
    if (url.pathname !== '/leads') return json({ error: 'not_found' }, 404, headers);
    if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405, headers);

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: 'invalid_json' }, 400, headers);
    }

    // Honeypot: accept and discard so bots see success and do not retry.
    if (typeof body.company_url === 'string' && body.company_url.trim() !== '') {
      return json({ ok: true }, 201, headers);
    }

    const name = String(body.name ?? '').trim().slice(0, 120);
    const email = String(body.email ?? '').trim().toLowerCase().slice(0, 254);
    const role = String(body.role ?? '').trim();
    const context = String(body.context ?? '').trim().slice(0, 1200);

    const invalid = [];
    if (!name) invalid.push('name');
    if (!EMAIL.test(email)) invalid.push('email');
    if (!ROLES.has(role)) invalid.push('role');
    if (invalid.length) return json({ error: 'invalid_fields', fields: invalid }, 422, headers);

    const cf = request.cf ?? {};

    try {
      await env.DB.prepare(
        `INSERT INTO leads (name, email, role, context, referrer, landing_query, country, user_agent)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
      )
        .bind(
          name,
          email,
          role,
          context,
          String(body.referrer ?? '').slice(0, 500),
          String(body.landing_query ?? '').slice(0, 500),
          cf.country ?? null,
          (request.headers.get('User-Agent') ?? '').slice(0, 300)
        )
        .run();
    } catch (err) {
      console.error('lead_insert_failed', err);
      return json({ error: 'storage_failed' }, 500, headers);
    }

    return json({ ok: true }, 201, headers);
  },
};
