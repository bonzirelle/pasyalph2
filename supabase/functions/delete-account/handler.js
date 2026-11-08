import { corsFor, json, readJson } from '../_shared/http.js';

export async function handleRequest(req, env = Deno.env, request = fetch) {
  const cors = corsFor(req, env);
  if (!cors.allowed) return json({ error: 'Origin not allowed' }, 403, cors.headers);
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors.headers });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405, cors.headers);

  try {
    const auth = req.headers.get('Authorization') ?? '';
    if (!auth.startsWith('Bearer ')) return json({ error: 'Sign in required' }, 401, cors.headers);
    const url = env.get('SUPABASE_URL');
    const key = env.get('SUPABASE_ANON_KEY');
    const service = env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !key || !service) {
      return json({ error: 'Account deletion is unavailable' }, 503, cors.headers);
    }

    const who = await request(`${url}/auth/v1/user`, {
      headers: { Authorization: auth, apikey: key },
      signal: AbortSignal.timeout(10000),
    });
    if (!who.ok) return json({ error: 'Sign in required' }, 401, cors.headers);
    const user = await who.json();
    if (!user.id) return json({ error: 'Sign in required' }, 401, cors.headers);

    const parsed = await readJson(req, 1024);
    if (parsed.error) return json({ error: parsed.error.message }, parsed.error.status, cors.headers);
    const body = parsed.value;
    if (!body || typeof body !== 'object' || Array.isArray(body) || body.confirm !== 'DELETE') {
      return json({ error: 'Explicit deletion confirmation is required' }, 400, cors.headers);
    }

    const age = Date.now() - Date.parse(user.last_sign_in_at ?? '');
    if (!Number.isFinite(age) || age < 0 || age > 5 * 60 * 1000) {
      return json({
        error: 'Sign in again before deleting your account. Password accounts can enter their current password. Google accounts must sign out and sign in again.',
      }, 403, cors.headers);
    }

    const headers = {
      apikey: service,
      Authorization: `Bearer ${service}`,
      'Content-Type': 'application/json',
    };
    const owned = await request(
      `${url}/rest/v1/places?owner_id=eq.${encodeURIComponent(user.id)}&status=eq.Verified&select=id&limit=1`,
      { headers, signal: AbortSignal.timeout(10000) },
    );
    if (!owned.ok) return json({ error: 'Unable to verify business ownership' }, 503, cors.headers);
    if ((await owned.json()).length) {
      return json({ error: 'Transfer verified business listings before deleting your account.' }, 409, cors.headers);
    }

    const revoke = await request(`${url}/auth/v1/logout?scope=global`, {
      method: 'POST',
      headers: { Authorization: auth, apikey: key },
      signal: AbortSignal.timeout(10000),
    });
    if (!revoke.ok) {
      return json({ error: 'Unable to revoke account sessions. Please try again.' }, 503, cors.headers);
    }

    for (let batch = 0; batch < 100; batch++) {
      const listing = await request(`${url}/storage/v1/object/list/pasyalph-media`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ prefix: user.id, limit: 100, offset: 0 }),
        signal: AbortSignal.timeout(10000),
      });
      if (!listing.ok) {
        return json({ error: 'Unable to check account photos. No account deletion was performed.' }, 503, cors.headers);
      }
      const files = await listing.json();
      if (!files.length) break;
      if (files.some((file) => !file.id)) {
        return json({ error: 'A nested photo folder needs administrator cleanup before account deletion.' }, 409, cors.headers);
      }
      const remove = await request(`${url}/storage/v1/object/pasyalph-media`, {
        method: 'DELETE',
        headers,
        body: JSON.stringify({ prefixes: files.map((file) => `${user.id}/${file.name}`) }),
        signal: AbortSignal.timeout(10000),
      });
      if (!remove.ok) {
        return json({ error: 'Some photos could not be removed. Please try again before deleting the account.' }, 503, cors.headers);
      }
      if (batch === 99) return json({ error: 'More photos remain. Please retry deletion.' }, 409, cors.headers);
    }

    const deleted = await request(`${url}/auth/v1/admin/users/${encodeURIComponent(user.id)}`, {
      method: 'DELETE',
      headers,
      body: JSON.stringify({ should_soft_delete: false }),
      signal: AbortSignal.timeout(10000),
    });
    if (!deleted.ok) {
      return json({ error: 'Account deletion could not be completed. Contact the operator for help.' }, 503, cors.headers);
    }
    return json({ deleted: true }, 200, cors.headers);
  } catch {
    return json({ error: 'Account deletion is temporarily unavailable' }, 503, cors.headers);
  }
}
