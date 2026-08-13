/**
 * OpenAI-compatible streaming client for mlx_lm.server / llama-server.
 */

async function probeReady(baseUrl) {
  const paths = ["/health", "/v1/models"];
  let lastError = "not started";
  for (const path of paths) {
    try {
      const res = await fetch(`${baseUrl}${path}`);
      if (res.ok) return { ok: true };
      // llama-server may return 503 while the model is still loading
      if (res.status === 503) return { ok: false, loading: true };
      lastError = `${path} HTTP ${res.status}`;
    } catch (err) {
      lastError = err instanceof Error ? err.message : String(err);
    }
  }
  return { ok: false, loading: false, lastError };
}

export async function waitForLlama(baseUrl, { timeoutMs = 180_000, intervalMs = 2_000 } = {}) {
  const deadline = Date.now() + timeoutMs;
  let lastError = "not started";
  while (Date.now() < deadline) {
    const status = await probeReady(baseUrl);
    if (status.ok) return true;
    lastError = status.lastError ?? (status.loading ? "loading" : lastError);
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  throw new Error(`inference server not ready at ${baseUrl}: ${lastError}`);
}

/**
 * Stream chat completion tokens. Yields plain text deltas.
 */
export async function* streamChat(baseUrl, { messages, maxTokens = 256, temperature = 0.7 }) {
  const model = process.env.MODEL_NAME ?? "ternary-bonsai-1.7b";
  const res = await fetch(`${baseUrl}/v1/chat/completions`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      model,
      messages,
      max_tokens: maxTokens,
      temperature,
      stream: true,
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`chat failed (${res.status}): ${body.slice(0, 400)}`);
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let leftover = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    leftover += decoder.decode(value, { stream: true });
    const lines = leftover.split("\n");
    leftover = lines.pop() ?? "";

    for (const raw of lines) {
      const line = raw.trim();
      if (!line.startsWith("data:")) continue;
      const payload = line.slice(5).trim();
      if (!payload || payload === "[DONE]") continue;
      let parsed;
      try {
        parsed = JSON.parse(payload);
      } catch {
        continue;
      }
      const delta = parsed?.choices?.[0]?.delta?.content;
      if (typeof delta === "string" && delta.length > 0) {
        yield delta;
      }
    }
  }
}
