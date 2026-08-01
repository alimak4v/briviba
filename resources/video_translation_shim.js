(() => {
  if (window.__brivibaVideoTranslationShimInstalled) return;
  window.__brivibaVideoTranslationShimInstalled = true;
  window.unsafeWindow = window.unsafeWindow || window;
  window.GM_info = window.GM_info || {
    script: { name: "Briviba Video Translation", version: "local", author: "Briviba" },
  };

  const storagePrefix = "__briviba_vot__";
  const readValue = (name, fallback) => {
    try {
      const raw = window.localStorage.getItem(storagePrefix + name);
      return raw === null ? fallback : JSON.parse(raw);
    } catch (_) {
      return fallback;
    }
  };
  const writeValue = (name, value) => {
    try {
      window.localStorage.setItem(storagePrefix + name, JSON.stringify(value));
    } catch (_) {}
  };
  const deleteValue = (name) => {
    try {
      window.localStorage.removeItem(storagePrefix + name);
    } catch (_) {}
  };
  const listValues = () => {
    try {
      const values = [];
      for (let index = 0; index < window.localStorage.length; ++index) {
        const key = window.localStorage.key(index);
        if (key && key.startsWith(storagePrefix)) {
          values.push(key.slice(storagePrefix.length));
        }
      }
      return values;
    } catch (_) {
      return [];
    }
  };

  window.GM_addStyle = window.GM_addStyle || ((css) => {
    const style = document.createElement("style");
    style.textContent = css;
    (document.head || document.documentElement).appendChild(style);
    return style;
  });
  window.GM_getValue = window.GM_getValue || ((name, fallback) => readValue(name, fallback));
  window.GM_setValue = window.GM_setValue || ((name, value) => writeValue(name, value));
  window.GM_deleteValue = window.GM_deleteValue || ((name) => deleteValue(name));
  window.GM_listValues = window.GM_listValues || (() => listValues());
  window.GM_notification = window.GM_notification || ((details) => {
    try {
      console.log(details);
    } catch (_) {}
  });
  window.GM = window.GM || {
    getValue: async (name, fallback) => readValue(name, fallback),
    getValues: async (defaults) => Object.fromEntries(
      Object.entries(defaults).map(([name, fallback]) => [name, readValue(name, fallback)]),
    ),
    setValue: async (name, value) => writeValue(name, value),
    deleteValue: async (name) => deleteValue(name),
    listValues: async () => listValues(),
  };

  const pendingRequests = new Map();
  let nextRequestId = 1;
  const BRIDGE_REQUEST_TYPE = "briviba-video-translation-request";
  const BRIDGE_RESPONSE_TYPE = "briviba-video-translation-response";
  const MAX_REQUEST_BODY_BYTES = 32 * 1024 * 1024;
  const utf8ByteLength = (text) => {
    let length = 0;
    for (let index = 0; index < text.length; index += 1) {
      const code = text.charCodeAt(index);
      if (code < 0x80) length += 1;
      else if (code < 0x800) length += 2;
      else if (code >= 0xd800 && code <= 0xdbff && index + 1 < text.length) {
        length += 4;
        index += 1;
      } else length += 3;
      if (length > MAX_REQUEST_BODY_BYTES) return length;
    }
    return length;
  };
  const requestBodyIsTooLarge = (data) => {
    if (data === undefined || data === null) return false;
    if (typeof data === "string") return utf8ByteLength(data) > MAX_REQUEST_BODY_BYTES;
    if (data instanceof Blob) return data.size > MAX_REQUEST_BODY_BYTES;
    if (data instanceof ArrayBuffer) return data.byteLength > MAX_REQUEST_BODY_BYTES;
    if (ArrayBuffer.isView(data)) return data.byteLength > MAX_REQUEST_BODY_BYTES;
    return false;
  };
  const bytesToBase64 = (bytes) => {
    let binary = "";
    for (let offset = 0; offset < bytes.length; offset += 0x8000) {
      binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
    }
    return btoa(binary);
  };
  const base64ToBytes = (text) => {
    const binary = atob(text || "");
    return Uint8Array.from(binary, (character) => character.charCodeAt(0));
  };
  const serializeHeaders = (headers) => {
    try {
      return Object.fromEntries(new Headers(headers || {}).entries());
    } catch (_) {
      return {};
    }
  };
  const serializeBody = (data) => {
    if (data === undefined || data === null) return { body: "", bodyEncoding: "none" };
    if (typeof data === "string") return { body: data, bodyEncoding: "utf8" };
    if (data instanceof ArrayBuffer) {
      return { body: bytesToBase64(new Uint8Array(data)), bodyEncoding: "base64" };
    }
    if (ArrayBuffer.isView(data)) {
      return {
        body: bytesToBase64(new Uint8Array(data.buffer, data.byteOffset, data.byteLength)),
        bodyEncoding: "base64",
      };
    }
    return { body: String(data), bodyEncoding: "utf8" };
  };
  const responseBody = (body, responseType) => {
    const bytes = base64ToBytes(body);
    if (responseType === "blob") return new Blob([bytes]);
    if (responseType === "arraybuffer") return bytes.buffer;
    const text = new TextDecoder().decode(bytes);
    if (responseType === "json") return JSON.parse(text);
    return text;
  };

  window.__brivibaVideoTranslationBridgeDidComplete = (message) => {
    const pending = pendingRequests.get(message.id);
    if (!pending) return;
    pendingRequests.delete(message.id);
    pending.settled = true;
    if (message.error) {
      const callback = message.error === "timeout" ? pending.ontimeout : pending.onerror;
      if (typeof callback === "function") callback({ error: message.message, statusText: message.message });
      return;
    }
    let response;
    try {
      response = responseBody(message.body, pending.responseType);
    } catch (error) {
      if (typeof pending.onerror === "function") {
        pending.onerror({ error: String(error), statusText: String(error) });
      }
      return;
    }
    if (typeof pending.onload === "function") {
      pending.onload({
        response,
        responseHeaders: message.responseHeaders || "",
        status: message.status || 0,
        statusText: message.statusText || "",
        finalUrl: message.finalUrl || pending.url,
      });
    }
  };
  window.addEventListener("message", (event) => {
    if (event.source === window && event.data?.type === BRIDGE_RESPONSE_TYPE) {
      window.__brivibaVideoTranslationBridgeDidComplete(event.data.payload);
    }
  });

  window.GM_xmlhttpRequest = window.GM_xmlhttpRequest || ((options) => {
    if (requestBodyIsTooLarge(options.data)) {
      const message = "Video translation request body is too large";
      if (typeof options.onerror === "function") options.onerror({ error: message, statusText: message });
      return { abort() {} };
    }
    const id = String(nextRequestId++);
    const bridge = {
      postMessage: (message) => window.postMessage({ type: BRIDGE_REQUEST_TYPE, payload: message }, "*"),
    };
    const pending = {
      onload: options.onload,
      onerror: options.onerror,
      ontimeout: options.ontimeout,
      onabort: options.onabort,
      responseType: options.responseType || "text",
      url: options.url,
      sent: false,
      settled: false,
    };
    pendingRequests.set(id, pending);
    const fail = (error) => {
      if (pending.settled) return;
      pendingRequests.delete(id);
      pending.settled = true;
      if (typeof options.onerror === "function") {
        options.onerror({ error: String(error), statusText: String(error) });
      }
    };
    if (!bridge || typeof bridge.postMessage !== "function") {
      pendingRequests.delete(id);
      pending.settled = true;
      if (typeof options.onerror === "function") {
        options.onerror({ error: "Native request bridge is unavailable", statusText: "Native request bridge is unavailable" });
      }
      return { abort() {} };
    }

    const send = (serializedBody) => {
      if (pending.settled) return;
      const serialized_body_bytes = serializedBody.bodyEncoding === "base64"
        ? Math.floor(serializedBody.body.length * 3 / 4)
          - (serializedBody.body.endsWith("==") ? 2 : serializedBody.body.endsWith("=") ? 1 : 0)
        : utf8ByteLength(serializedBody.body);
      if (serialized_body_bytes > MAX_REQUEST_BODY_BYTES) {
        fail("Video translation request body is too large");
        return;
      }
      try {
        bridge.postMessage({
          action: "request",
          id,
          method: options.method || "GET",
          url: options.url,
          headers: serializeHeaders(options.headers),
          body: serializedBody.body,
          bodyEncoding: serializedBody.bodyEncoding,
          timeout: Number.isFinite(options.timeout) ? options.timeout : 15000,
        });
        pending.sent = true;
      } catch (error) {
        fail(error);
      }
    };
    if (options.data instanceof Blob) {
      options.data.arrayBuffer().then((buffer) => send(serializeBody(buffer))).catch((error) => {
        fail(error);
      });
    } else {
      send(serializeBody(options.data));
    }

    return {
      abort: () => {
        if (pending.settled) return;
        pending.settled = true;
        pendingRequests.delete(id);
        if (pending.sent) {
          try {
            bridge.postMessage({ action: "abort", id });
          } catch (_) {}
        }
        if (typeof pending.onabort === "function") pending.onabort();
      },
    };
  });
})();
