const { app, BrowserWindow, ipcMain, shell } = require("electron");
const path = require("path");
const { Agent, fetch: undiciFetch } = require("undici");

const DEFAULT_BACKEND =
  "https://customer-intent-backend-customer-intent-demo.apps.tiago-cluster.sandbox897.opentlc.com/api/v1/routing";

function buildFetch(insecureTls) {
  if (!insecureTls) {
    return globalThis.fetch.bind(globalThis);
  }
  const agent = new Agent({ connect: { rejectUnauthorized: false } });
  return (url, options) => undiciFetch(url, { ...options, dispatcher: agent });
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1280,
    height: 820,
    minWidth: 960,
    minHeight: 640,
    backgroundColor: "#151515",
    title: "Customer Intent Demo",
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  win.loadFile(path.join(__dirname, "src", "index.html"));
  win.setMenuBarVisibility(false);
}

ipcMain.handle("route-request", async (_event, payload) => {
  const url = payload.url || DEFAULT_BACKEND;
  const fetchFn = buildFetch(Boolean(payload.insecureTls));
  const response = await fetchFn(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", Accept: "application/json" },
    body: JSON.stringify({
      text: payload.text,
      correlationId: payload.correlationId,
    }),
  });

  const bodyText = await response.text();
  let body;
  try {
    body = JSON.parse(bodyText);
  } catch {
    body = { error: bodyText || response.statusText };
  }

  if (!response.ok) {
    return {
      ok: false,
      status: response.status,
      error: body.error || body.message || bodyText || response.statusText,
    };
  }

  return { ok: true, data: body };
});

ipcMain.handle("get-default-backend", () => DEFAULT_BACKEND);

ipcMain.on("open-external", (_event, url) => {
  shell.openExternal(url);
});

app.whenReady().then(createWindow);

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});

app.on("activate", () => {
  if (BrowserWindow.getAllWindows().length === 0) {
    createWindow();
  }
});
