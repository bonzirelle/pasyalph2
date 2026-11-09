import { corsFor, json, readJson } from '../_shared/http.js';

const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function handleRequest(req, env = Deno.env, request = fetch) {
  const cors = corsFor(req, env);
  if (!cors.allowed) return json({ error: 'Origin not allowed' }, 403, cors.headers);
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors.headers });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405, cors.headers);

  const auth = req.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ')) return json({ error: 'Sign in required' }, 401, cors.headers);

  const url = env.get('SUPABASE_URL');
  const anonKey = env.get('SUPABASE_ANON_KEY');
  const serviceKey = env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !anonKey || !serviceKey) {
    return json({ error: 'Admin account creation is unavailable' }, 503, cors.headers);
  }

  try {
    const who = await request(`${url}/auth/v1/user`, {
      headers: { Authorization: auth, apikey: anonKey },
      signal: AbortSignal.timeout(10000),
    });
    if (!who.ok) return json({ error: 'Sign in required' }, 401, cors.headers);
    const currentUser = await who.json();
    if (!currentUser.id || !currentUser.email_confirmed_at) {
      return json({ error: 'Verify your email before creating an administrator' }, 403, cors.headers);
    }

    const profile = await request(
      `${url}/rest/v1/profiles?id=eq.${encodeURIComponent(currentUser.id)}&select=role`,
      {
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
        },
        signal: AbortSignal.timeout(10000),
      },
    );
    if (!profile.ok) return json({ error: 'Unable to verify administrator access' }, 503, cors.headers);
    const profiles = await profile.json();
    if (!profiles.some((row) => row.role === 'admin')) {
      return json({ error: 'Administrator access required' }, 403, cors.headers);
    }

    const parsed = await readJson(req, 4096);
    if (parsed.error) return json({ error: parsed.error.message }, parsed.error.status, cors.headers);
    const body = parsed.value;
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      return json({ error: 'Enter an email address and password' }, 400, cors.headers);
    }
    const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
    const password = body.password;
    if (!emailPattern.test(email) || email.length > 254) {
      return json({ error: 'Enter a valid email address' }, 400, cors.headers);
    }
    if (typeof password !== 'string' || password.length < 12 || password.length > 128) {
      return json({ error: 'Password must be between 12 and 128 characters' }, 400, cors.headers);
    }

    const created = await request(`${url}/auth/v1/admin/users`, {
      method: 'POST',
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ email, password, email_confirm: true }),
      signal: AbortSignal.timeout(10000),
    });
    if (created.status === 422 || created.status === 409) {
      return json({ error: 'An account with this email already exists' }, 409, cors.headers);
    }
    if (!created.ok) {
      return json({ error: 'The administrator account could not be created' }, 503, cors.headers);
    }
    const newUser = await created.json();
    if (!newUser.id) return json({ error: 'The administrator account could not be created' }, 503, cors.headers);

    const assigned = await request(`${url}/rest/v1/profiles?on_conflict=id`, {
      method: 'POST',
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        'Content-Type': 'application/json',
        Prefer: 'resolution=merge-duplicates,return=minimal',
      },
      body: JSON.stringify({ id: newUser.id, role: 'admin' }),
      signal: AbortSignal.timeout(10000),
    });
    if (!assigned.ok) {
      const cleanup = await request(
        `${url}/auth/v1/admin/users/${encodeURIComponent(newUser.id)}`,
        {
          method: 'DELETE',
          headers: {
            apikey: serviceKey,
            Authorization: `Bearer ${serviceKey}`,
          },
          signal: AbortSignal.timeout(10000),
        },
      );
      if (!cleanup.ok) {
        return json({
          error: 'Administrator setup was incomplete and automatic cleanup failed. Contact the project operator.',
        }, 503, cors.headers);
      }
      return json({ error: 'The admin role could not be assigned; the new account was removed' }, 503, cors.headers);
    }

    return json({ id: newUser.id, email, role: 'admin' }, 201, cors.headers);
  } catch {
    return json({ error: 'Admin account creation is temporarily unavailable' }, 503, cors.headers);
  }
}
