const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(
  path.join(__dirname, "..", "resources", "video_translation_relay.js"),
  "utf8",
);

const nativeMessages = [];
const pageMessages = [];
const listeners = [];
const context = {
  console,
  addEventListener: (type, listener) => {
    if (type === "message") listeners.push(listener);
  },
  postMessage: (message) => pageMessages.push(message),
  webkit: {
    messageHandlers: {
      brivibaVideoTranslation: {
        postMessage: (message) => nativeMessages.push(message),
      },
    },
  },
};
context.window = context;
context.globalThis = context;
const vmContext = vm.createContext(context);
vm.runInContext(source, vmContext);
assert.equal(listeners.length, 1);

context.relayTestListener = listeners[0];
const dispatchFromPage = (payload) => {
  context.relayTestPayload = payload;
  vm.runInContext(`relayTestListener({
    source: window,
    data: { type: "briviba-video-translation-request", payload: relayTestPayload },
  })`, vmContext);
};

dispatchFromPage({
  action: "request",
  id: "1",
  method: "POST",
  url: "https://api.browser.yandex.ru/video-translation/translate",
  headers: { "content-type": "application/octet-stream" },
  body: "AQID",
  bodyEncoding: "base64",
  timeout: 5000,
  untrustedExtraField: "must not cross the process boundary",
});
assert.equal(nativeMessages.length, 1);
assert.equal(nativeMessages[0].id, "1");
assert.equal(Object.hasOwn(nativeMessages[0], "untrustedExtraField"), false);

dispatchFromPage({
  action: "request",
  id: "2",
  method: "GET",
  url: `https://api.browser.yandex.ru/${"x".repeat(4096)}`,
  headers: {},
  body: "",
  bodyEncoding: "none",
  timeout: 5000,
});
assert.equal(nativeMessages.length, 1, "oversized URL must not cross into the native process");
assert.equal(pageMessages.at(-1).payload.id, "2");
assert.equal(pageMessages.at(-1).payload.error, "network");

dispatchFromPage({ action: "abort", id: "1" });
assert.equal(nativeMessages.length, 2);
assert.equal(nativeMessages[1].action, "abort");

context.__brivibaVideoTranslationBridgeDidComplete({
  id: "1",
  status: 200,
  body: "",
});
assert.equal(pageMessages.at(-1).type, "briviba-video-translation-response");
assert.equal(pageMessages.at(-1).payload.id, "1");
