// kondate-loop: Gemini APIプロキシ(Supabase Edge Function)
// 目的: Gemini APIキーをサーバー側の secret として保持し、クライアント(公開HTML)に露出させない。
// アプリは model / contents / generationConfig を送るだけ。キーはこの関数が付与する。
//
// デプロイ:
//   1) Supabase ダッシュボード → Edge Functions → Deploy a new function → 名前 "gemini" → このコードを貼って Deploy
//      (または CLI: supabase functions deploy gemini --project-ref twidxiiwgivcykoppgdj)
//   2) Project Settings → Edge Functions → Secrets に GEMINI_API_KEY を登録
//      (または CLI: supabase secrets set GEMINI_API_KEY=AIza... --project-ref twidxiiwgivcykoppgdj)
//
// 呼び出し(アプリ側): POST {SUPABASE_URL}/functions/v1/gemini
//   headers: { apikey, Authorization: Bearer <publishable/anon key>, Content-Type: application/json }
//   body: { model, contents, generationConfig }

const ALLOWED_ORIGINS = [
  "https://nobumei.github.io",
  "http://127.0.0.1:8791",
  "http://localhost:8791",
];

function corsHeaders(origin: string | null): Record<string, string> {
  // 許可オリジンならそれを返し、そうでなければ既定(GitHub Pages)を返す
  const allow = origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    "Access-Control-Allow-Origin": allow,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  const cors = corsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    return new Response(JSON.stringify({ error: "server_key_not_configured" }), {
      status: 500,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  let body: { model?: string; contents?: unknown; generationConfig?: unknown };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const model = typeof body.model === "string" && body.model ? body.model : "gemini-2.5-flash";
  if (!body.contents) {
    return new Response(JSON.stringify({ error: "missing_contents" }), {
      status: 400,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }

  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${apiKey}`;

  try {
    const gemRes = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ contents: body.contents, generationConfig: body.generationConfig }),
    });
    const text = await gemRes.text();
    // Geminiのステータス/本文をそのまま透過(アプリ側の 429/401 等のハンドリングを維持)
    return new Response(text, {
      status: gemRes.status,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: "upstream_fetch_failed", detail: String(e) }), {
      status: 502,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  }
});
