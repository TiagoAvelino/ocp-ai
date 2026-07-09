const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("demoApi", {
  routeRequest: (payload) => ipcRenderer.invoke("route-request", payload),
  getDefaultBackend: () => ipcRenderer.invoke("get-default-backend"),
  openExternal: (url) => ipcRenderer.send("open-external", url),
});
