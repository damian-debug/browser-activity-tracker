import { registerListeners, initialize } from "./tracker";

// MV3: listeners MUST be registered synchronously at the top level so Chrome can
// wake the service worker for these events. Do this first, before any await.
registerListeners();

// Bootstrap (load settings, restore the in-flight session, reconcile the active
// tab). Safe to call from multiple entry points — it runs once per SW lifetime.
chrome.runtime.onInstalled.addListener(() => initialize());
chrome.runtime.onStartup.addListener(() => initialize());
initialize();
