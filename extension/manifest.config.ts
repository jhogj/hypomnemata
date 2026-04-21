import { defineManifest } from "@crxjs/vite-plugin";

export default defineManifest({
  manifest_version: 3,
  name: "Hypomnemata",
  version: "0.1.0",
  description: "Captura de conteúdo para o Hypomnemata local",
  action: {
    default_popup: "src/popup/index.html",
    default_title: "Hypomnemata — capturar",
  },
  background: {
    service_worker: "src/background.ts",
    type: "module",
  },
  permissions: ["activeTab", "tabs", "storage", "scripting"],
  host_permissions: ["http://127.0.0.1/*", "http://localhost/*", "<all_urls>"],
  commands: {
    "capture-tab": {
      suggested_key: {
        default: "Ctrl+Shift+Y",
        mac: "Command+Shift+Y",
      },
      description: "Capturar aba atual no Hypomnemata",
    },
  },
});
