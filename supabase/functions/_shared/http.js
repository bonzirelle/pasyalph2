const baseHeaders = {
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Cache-Control': 'no-store',
  'Vary': 'Origin',
  'X-Content-Type-Options': 'nosniff',
};

export function corsFor(request, env) {
  const origin = request.headers.get('Origin');
  if (!origin) return { allowed: true, headers: { ...baseHeaders } };

  const allowedOrigins = new Set(
    (env.get('APP_ALLOWED_ORIGINS') ?? '')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean),
  );
  if (!allowedOrigins.has(origin)) {
    return { allowed: false, headers: { ...baseHeaders } };
  }

  return {
    allowed: true,
    headers: {
      ...baseHeaders,
      'Access-Control-Allow-Origin': origin,
    },
  };
}

export function json(body, status, headers) {
  return Response.json(body, { status, headers });
}

export async function readJson(request, maxBytes) {
  const contentType = request.headers.get('Content-Type') ?? '';
  if (!/^application\/json(?:\s*;|$)/i.test(contentType)) {
    return { error: { status: 415, message: 'Send a JSON request.' } };
  }

  if (!request.body) {
    return { error: { status: 400, message: 'Invalid request.' } };
  }

  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > maxBytes) {
      await reader.cancel();
      return { error: { status: 413, message: 'Request is too large.' } };
    }
    chunks.push(value);
  }

  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }

  try {
    return { value: JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)) };
  } catch {
    return { error: { status: 400, message: 'Invalid request.' } };
  }
}
