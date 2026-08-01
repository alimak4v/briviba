(() => {
  if (window.__brivibaVideoTranslationRelayInstalled) return;
  window.__brivibaVideoTranslationRelayInstalled = true;

  const REQUEST_TYPE = "briviba-video-translation-request";
  const RESPONSE_TYPE = "briviba-video-translation-response";
  const MAX_BODY_BYTES = 32 * 1024 * 1024;
  const MAX_BASE64_BODY_CHARACTERS = Math.ceil(32 * 1024 * 1024 * 4 / 3) + 4;
  const MAX_URL_CHARACTERS = 4096;
  const MAX_HEADERS = 64;
  const MAX_HEADER_NAME_CHARACTERS = 256;
  const MAX_HEADER_VALUE_CHARACTERS = 8192;
  const handler = window.webkit?.messageHandlers?.brivibaVideoTranslation;

  const reject = (id, message) => {
    window.postMessage({
      type: RESPONSE_TYPE,
      payload: { id, error: "network", message },
    }, "*");
  };

  const sanitizedHeaders = (headers) => {
    if (headers === undefined || headers === null) return {};
    if (typeof headers !== "object" || Array.isArray(headers)) return null;
    const entries = Object.entries(headers);
    if (entries.length > MAX_HEADERS || !entries.every(([name, value]) => (
      typeof name === "string" && name.length <= MAX_HEADER_NAME_CHARACTERS
      && typeof value === "string" && value.length <= MAX_HEADER_VALUE_CHARACTERS
    ))) return null;
    return Object.fromEntries(entries);
  };

  const utf8BodyIsTooLarge = (text) => {
    let bytes = 0;
    for (let index = 0; index < text.length; index += 1) {
      const code = text.charCodeAt(index);
      if (code < 0x80) bytes += 1;
      else if (code < 0x800) bytes += 2;
      else if (code >= 0xD800 && code <= 0xDBFF
          && index + 1 < text.length
          && text.charCodeAt(index + 1) >= 0xDC00
          && text.charCodeAt(index + 1) <= 0xDFFF) {
        bytes += 4;
        index += 1;
      } else bytes += 3;
      if (bytes > MAX_BODY_BYTES) return true;
    }
    return false;
  };

  const base64BodyIsTooLarge = (text) => {
    if (text.length > MAX_BASE64_BODY_CHARACTERS) return true;
    const padding = text.endsWith("==") ? 2 : text.endsWith("=") ? 1 : 0;
    return Math.floor(text.length * 3 / 4) - padding > MAX_BODY_BYTES;
  };

  window.addEventListener("message", (event) => {
    if (event.source !== window || event.data?.type !== REQUEST_TYPE) return;
    const message = event.data.payload;
    if (!message || typeof message !== "object" || Array.isArray(message)) return;
    if (typeof message.id !== "string" || message.id.length === 0 || message.id.length > 64) return;
    if (message.action === "abort") {
      try {
        handler?.postMessage({ action: "abort", id: message.id });
      } catch (_) {}
      return;
    }
    if (message.action !== "request") return;
    if (typeof message.url !== "string" || message.url.length === 0
        || message.url.length > MAX_URL_CHARACTERS) {
      reject(message.id, "Video translation request URL is invalid or too long");
      return;
    }
    const headers = sanitizedHeaders(message.headers);
    const bodyEncoding = message.bodyEncoding === "base64" ? "base64" : "none";
    const bodyIsTooLarge = typeof message.body === "string" && (bodyEncoding === "base64"
      ? base64BodyIsTooLarge(message.body) : utf8BodyIsTooLarge(message.body));
    if (typeof message.body !== "string" || bodyIsTooLarge || headers === null) {
      reject(message.id, "Video translation request metadata is too large");
      return;
    }
    if (!handler || typeof handler.postMessage !== "function") {
      reject(message.id, "Native request bridge is unavailable");
      return;
    }
    try {
      handler.postMessage({
        action: "request",
        id: message.id,
        method: typeof message.method === "string" ? message.method.slice(0, 16) : "GET",
        url: message.url,
        headers,
        body: message.body,
        bodyEncoding,
        timeout: Number.isFinite(message.timeout) ? message.timeout : 0,
        responseType: typeof message.responseType === "string"
          ? message.responseType.slice(0, 32) : "text",
      });
    } catch (error) {
      reject(message.id, String(error));
    }
  });

  window.__brivibaVideoTranslationBridgeDidComplete = (payload) => {
    window.postMessage({ type: RESPONSE_TYPE, payload }, "*");
  };
})();
