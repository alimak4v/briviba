const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(
  path.join(__dirname, "..", "resources", "video_translation_shim.js"),
  "utf8",
);

const postedMessages = [];
let postMessageError;
const messageListeners = [];
const storage = new Map();
const context = {
  AbortController,
  Blob,
  Headers,
  Uint8Array,
  ArrayBuffer,
  atob,
  btoa,
  console,
  document: {
    createElement: () => ({}),
    documentElement: { appendChild() {} },
    head: { appendChild() {} },
  },
  localStorage: {
    getItem: (key) => storage.get(key) ?? null,
    setItem: (key, value) => storage.set(key, value),
    removeItem: (key) => storage.delete(key),
    key: (index) => [...storage.keys()][index] ?? null,
    get length() {
      return storage.size;
    },
  },
  addEventListener: (type, listener) => {
    if (type === "message") messageListeners.push(listener);
  },
  postMessage: (envelope) => {
    if (postMessageError) throw postMessageError;
    if (envelope?.type === "briviba-video-translation-request") {
      postedMessages.push(envelope.payload);
    }
  },
};
context.window = context;
context.globalThis = context;
vm.runInNewContext(source, context);

async function run() {
  let loadedResponse;
  const request = context.GM_xmlhttpRequest({
    method: "POST",
    url: "https://api.browser.yandex.ru/video-translation/translate",
    headers: { "Content-Type": "application/octet-stream" },
    data: new Uint8Array([1, 2, 3]),
    responseType: "blob",
    timeout: 5000,
    onload: (response) => {
      loadedResponse = response;
    },
  });

  assert.equal(postedMessages.length, 1);
  assert.deepEqual(
    JSON.parse(JSON.stringify(postedMessages[0])),
    {
      action: "request",
      id: postedMessages[0].id,
      method: "POST",
      url: "https://api.browser.yandex.ru/video-translation/translate",
      headers: { "content-type": "application/octet-stream" },
      body: "AQID",
      bodyEncoding: "base64",
      timeout: 5000,
    },
  );

  context.__brivibaVideoTranslationBridgeDidComplete({
    id: postedMessages[0].id,
    status: 200,
    statusText: "OK",
    finalUrl: "https://api.browser.yandex.ru/video-translation/translate",
    responseHeaders: "content-type: application/octet-stream",
    body: "BAUG",
  });

  assert.equal(loadedResponse.status, 200);
  assert.equal(loadedResponse.statusText, "OK");
  assert.equal(loadedResponse.finalUrl, "https://api.browser.yandex.ru/video-translation/translate");
  assert.equal(loadedResponse.responseHeaders, "content-type: application/octet-stream");
  assert.ok(loadedResponse.response instanceof Blob);

  request.abort();
  assert.equal(postedMessages.length, 1, "abort after onload must be a no-op");

  let resolveBlob;
  const delayedBlob = new Blob([new Uint8Array([7, 8, 9])]);
  delayedBlob.arrayBuffer = () => new Promise((resolve) => {
    resolveBlob = resolve;
  });
  let abortCallbackCount = 0;
  const delayedRequest = context.GM_xmlhttpRequest({
    method: "PUT",
    url: "https://api.browser.yandex.ru/video-translation/audio",
    data: delayedBlob,
    timeout: 0,
    onabort: () => {
      abortCallbackCount += 1;
    },
  });
  assert.equal(postedMessages.length, 1, "Blob body must be serialized before sending");
  delayedRequest.abort();
  assert.equal(abortCallbackCount, 1);
  assert.equal(postedMessages.length, 1, "unsent Blob request must not post an abort");
  resolveBlob(new Uint8Array([7, 8, 9]).buffer);
  await Promise.resolve();
  await Promise.resolve();
  assert.equal(postedMessages.length, 1, "aborted Blob request must never be sent");

  let regularAbortCallbackCount = 0;
  let regularLoadCallbackCount = 0;
  const regularRequest = context.GM_xmlhttpRequest({
    method: "GET",
    url: "https://api.browser.yandex.ru/video-translation/status",
    timeout: 0,
    onabort: () => {
      regularAbortCallbackCount += 1;
    },
    onload: () => {
      regularLoadCallbackCount += 1;
    },
  });
  assert.equal(postedMessages.length, 2);
  assert.equal(postedMessages[1].timeout, 0, "timeout: 0 must reach the native bridge");
  regularRequest.abort();
  assert.equal(regularAbortCallbackCount, 1);
  assert.equal(postedMessages.length, 3);
  assert.equal(postedMessages[2].action, "abort");
  context.__brivibaVideoTranslationBridgeDidComplete({
    id: postedMessages[1].id,
    status: 200,
    statusText: "OK",
    finalUrl: "https://api.browser.yandex.ru/video-translation/status",
    responseHeaders: "",
    body: "",
  });
  assert.equal(regularLoadCallbackCount, 0, "aborted request must ignore later completion");

  let invalidJsonErrors = 0;
  let invalidJsonLoads = 0;
  context.GM_xmlhttpRequest({
    method: "GET",
    url: "https://api.browser.yandex.ru/video-translation/status",
    responseType: "json",
    onload: () => {
      invalidJsonLoads += 1;
    },
    onerror: () => {
      invalidJsonErrors += 1;
    },
  });
  assert.equal(postedMessages.length, 4);
  context.__brivibaVideoTranslationBridgeDidComplete({
    id: postedMessages[3].id,
    status: 200,
    statusText: "OK",
    finalUrl: "https://api.browser.yandex.ru/video-translation/status",
    responseHeaders: "content-type: application/json",
    body: "bm90LWpzb24=",
  });
  assert.equal(invalidJsonLoads, 0);
  assert.equal(invalidJsonErrors, 1, "invalid JSON must settle through onerror");

  let postErrors = 0;
  postMessageError = new Error("bridge detached");
  context.GM_xmlhttpRequest({
    method: "GET",
    url: "https://api.browser.yandex.ru/video-translation/status",
    onerror: () => {
      postErrors += 1;
    },
  });
  postMessageError = undefined;
  assert.equal(postErrors, 1, "postMessage failure must settle through onerror");
  assert.equal(postedMessages.length, 4);

  let detachedAbortCalls = 0;
  const detachedAbortRequest = context.GM_xmlhttpRequest({
    method: "GET",
    url: "https://api.browser.yandex.ru/video-translation/status",
    onabort: () => {
      detachedAbortCalls += 1;
    },
  });
  assert.equal(postedMessages.length, 5);
  postMessageError = new Error("bridge detached during abort");
  assert.doesNotThrow(() => detachedAbortRequest.abort());
  postMessageError = undefined;
  assert.equal(detachedAbortCalls, 1, "detached bridge must not prevent abort settlement");

  let oversizedErrors = 0;
  const oversizedBlob = new Blob([]);
  Object.defineProperty(oversizedBlob, "size", { value: 32 * 1024 * 1024 + 1 });
  context.GM_xmlhttpRequest({
    method: "POST",
    url: "https://api.browser.yandex.ru/video-translation/translate",
    data: oversizedBlob,
    onerror: () => {
      oversizedErrors += 1;
    },
  });
  assert.equal(oversizedErrors, 1, "oversized Blob must be rejected before serialization");
  assert.equal(postedMessages.length, 5);
}

run().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
