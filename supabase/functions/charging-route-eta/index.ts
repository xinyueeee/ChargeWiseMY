import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info',
};

// api.openrouteservice.org was sunset 2026-08-24 in favour of api.heigit.org's
// unified <domain>/<service>/<version> structure. Existing ORS API keys and
// quotas carry over unchanged - see
// https://ask.openrouteservice.org/t/deprecating-api-openrouteservice-org-in-favour-of-api-heigit-org/7912
const ORS_MATRIX_URL = 'https://api.heigit.org/openrouteservice/v2/matrix/driving-car';
const MAX_CANDIDATES = 5;

type Candidate = { id: string; lat: number; lng: number };
type EtaContext = { originLat: number; originLng: number; candidates: Candidate[] };

class EtaContextValidationError extends Error {
  constructor(readonly field: string) {
    super(`Invalid route ETA context field: ${field}`);
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function getDefaultPublishableKey(): string | null {
  const rawKeys = Deno.env.get('SUPABASE_PUBLISHABLE_KEYS');
  if (!rawKeys) {
    console.error('Route ETA Supabase environment is missing SUPABASE_PUBLISHABLE_KEYS.');
    return null;
  }
  try {
    const keys = JSON.parse(rawKeys) as Record<string, unknown>;
    const defaultKey = keys.default;
    if (typeof defaultKey !== 'string' || defaultKey.trim().length === 0) {
      console.error('Route ETA Supabase publishable key configuration has no default key.');
      return null;
    }
    return defaultKey;
  } catch {
    console.error('Route ETA Supabase publishable key configuration is not valid JSON.');
    return null;
  }
}

function safeId(value: unknown, name: string): string {
  if (typeof value !== 'string') throw new Error(`${name} must be text.`);
  const trimmed = value.trim();
  if (!trimmed || trimmed.length > 100) throw new Error(`${name} is invalid.`);
  return trimmed;
}

function lat(value: unknown, name: string): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < -90 || value > 90) {
    throw new Error(`${name} must be a valid latitude.`);
  }
  return value;
}

function lng(value: unknown, name: string): number {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < -180 || value > 180) {
    throw new Error(`${name} must be a valid longitude.`);
  }
  return value;
}

function validateContext(input: unknown): EtaContext {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    throw new EtaContextValidationError('body');
  }
  const body = input as Record<string, unknown>;
  const allowedKeys = new Set(['originLat', 'originLng', 'candidates']);
  for (const key of Object.keys(body)) {
    if (!allowedKeys.has(key)) throw new EtaContextValidationError(key);
  }
  let originLat: number, originLng: number;
  try {
    originLat = lat(body.originLat, 'originLat');
    originLng = lng(body.originLng, 'originLng');
  } catch {
    throw new EtaContextValidationError('origin');
  }
  if (!Array.isArray(body.candidates) || body.candidates.length < 1 || body.candidates.length > MAX_CANDIDATES) {
    throw new EtaContextValidationError('candidates');
  }
  const candidates = body.candidates.map((entry, index) => {
    if (!entry || typeof entry !== 'object' || Array.isArray(entry)) {
      throw new EtaContextValidationError(`candidates[${index}]`);
    }
    const c = entry as Record<string, unknown>;
    const candidateKeys = new Set(['id', 'lat', 'lng']);
    for (const key of Object.keys(c)) {
      if (!candidateKeys.has(key)) throw new EtaContextValidationError(`candidates[${index}].${key}`);
    }
    try {
      return {
        id: safeId(c.id, `candidates[${index}].id`),
        lat: lat(c.lat, `candidates[${index}].lat`),
        lng: lng(c.lng, `candidates[${index}].lng`),
      };
    } catch {
      throw new EtaContextValidationError(`candidates[${index}]`);
    }
  });
  return { originLat, originLng, candidates };
}

Deno.serve(async (request: Request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (request.method !== 'POST') return json({ error: 'Method not allowed.' }, 405);

  try {
    const authorization = request.headers.get('Authorization');
    if (!authorization?.startsWith('Bearer ')) return json({ error: 'Authentication required.' }, 401);

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const publishableKey = getDefaultPublishableKey();
    if (!supabaseUrl || !publishableKey) {
      console.error('Route ETA Supabase authentication configuration is incomplete.');
      return json({ error: 'Server authentication is not configured.' }, 500);
    }
    const supabase = createClient(supabaseUrl, publishableKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      console.warn('Route ETA user authentication failed.', { status: authError?.status ?? null });
      return json({ error: 'Authentication required.' }, 401);
    }

    const contentLength = Number(request.headers.get('content-length') ?? 0);
    if (contentLength > 4_000) return json({ error: 'Request is too large.' }, 413);
    let context: EtaContext;
    try {
      context = validateContext(await request.json());
    } catch (error) {
      const field = error instanceof EtaContextValidationError ? error.field : 'body';
      console.warn('Route ETA context validation failed.', { field });
      return json({ error: 'invalid_route_context', field }, 400);
    }

    const apiKey = Deno.env.get('ORS_API_KEY');
    if (!apiKey) {
      console.error('Route ETA OpenRouteService provider configuration is missing.');
      return json({ error: 'ETA service is not configured.' }, 503);
    }

    // ORS coordinates are [lng, lat]. Index 0 is always the origin; the
    // candidates follow in the order the client sent them, so indexes map
    // straight back to context.candidates.
    const locations = [
      [context.originLng, context.originLat],
      ...context.candidates.map((c) => [c.lng, c.lat]),
    ];
    const destinations = context.candidates.map((_, index) => index + 1);

    const abortController = new AbortController();
    const timeout = setTimeout(() => abortController.abort(), 15_000);
    let orsResponse: Response;
    try {
      orsResponse = await fetch(ORS_MATRIX_URL, {
        method: 'POST',
        headers: {
          Authorization: apiKey,
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        signal: abortController.signal,
        body: JSON.stringify({
          locations,
          sources: [0],
          destinations,
          metrics: ['distance', 'duration'],
        }),
      });
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') {
        console.error('ORS matrix request timed out.');
        return json({ error: 'ETA could not be calculated.' }, 504);
      }
      throw error;
    } finally {
      clearTimeout(timeout);
    }

    if (!orsResponse.ok) {
      const providerFailure = await orsResponse.json().catch(() => null);
      const providerMessage = typeof providerFailure?.error?.message === 'string'
        ? providerFailure.error.message.slice(0, 240)
        : typeof providerFailure?.error === 'string'
          ? providerFailure.error.slice(0, 240)
          : null;
      console.error('ORS matrix request rejected.', {
        status: orsResponse.status,
        message: providerMessage,
      });
      if (orsResponse.status === 429) {
        return json({ error: 'ETA service is temporarily rate limited.' }, 429);
      }
      if (orsResponse.status === 401 || orsResponse.status === 403) {
        return json({ error: 'ors_authentication_failed' }, 502);
      }
      return json({ error: 'ETA could not be calculated.' }, 502);
    }

    const payload = await orsResponse.json();
    const distances = payload?.distances?.[0];
    const durations = payload?.durations?.[0];
    if (!Array.isArray(distances) || !Array.isArray(durations) ||
        distances.length !== context.candidates.length ||
        durations.length !== context.candidates.length) {
      console.error('ORS matrix returned an unexpected shape.');
      return json({ error: 'invalid_ors_response' }, 502);
    }

    const results = context.candidates.map((candidate, index) => {
      const distanceM = distances[index];
      const durationS = durations[index];
      // ORS returns null for a pair it couldn't route (e.g. no road access);
      // pass that through as null rather than fabricating a number.
      return {
        id: candidate.id,
        distanceKm: typeof distanceM === 'number' ? distanceM / 1000 : null,
        durationMinutes: typeof durationS === 'number' ? durationS / 60 : null,
      };
    });

    return json({ results });
  } catch (error) {
    console.error('charging-route-eta failed:', error);
    return json({ error: 'route_eta_internal_error' }, 500);
  }
});
