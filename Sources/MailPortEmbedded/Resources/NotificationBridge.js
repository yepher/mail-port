(() => {
  "use strict";
  if (location.protocol !== "https:" || window.top !== window ||
      !["calendar.google.com", "mail.google.com"].includes(location.hostname)) return;
  const native = window.webkit?.messageHandlers?.mailPortNotifications;
  if (!native || window.__mailportNotifications) return;
  let permission = "__MAILPORT_PERMISSION__";
  const notifications = new Map();
  const requests = new Map();
  const makeID = () => "mp-" + crypto.randomUUID();
  const permissionStatus = new EventTarget();
  Object.defineProperty(permissionStatus, "state", {get: () => permission === "default" ? "prompt" : permission});
  permissionStatus.onchange = null;
  const permissions = window.navigator?.permissions;
  if (permissions?.query) {
    const query = permissions.query.bind(permissions);
    Object.defineProperty(permissions, "query", {configurable: true, value: descriptor =>
      descriptor?.name === "notifications" ? Promise.resolve(permissionStatus) : query(descriptor)});
  }
  function emit(notification, type) {
    notification.dispatchEvent(new Event(type));
    const callback = notification["on" + type];
    if (typeof callback === "function") callback.call(notification, new Event(type));
  }
  class MailPortNotification extends EventTarget {
    constructor(title, options = {}) {
      super();
      if (permission !== "granted") throw new DOMException("Notifications need permission in MailPort.", "NotAllowedError");
      this.title = String(title);
      this.body = String(options.body ?? "");
      this.tag = String(options.tag ?? "");
      this.data = options.data ?? null;
      this.silent = options.silent === true;
      this.onclick = this.onclose = this.onerror = this.onshow = null;
      this._mailportID = makeID();
      notifications.set(this._mailportID, this);
      native.postMessage({kind: "show", id: this._mailportID, title: this.title.slice(0,256),
        body: this.body.slice(0,2048), tag: this.tag.slice(0,256), silent: this.silent});
    }
    static get permission() { return permission; }
    static get maxActions() { return 0; }
    static requestPermission(callback) {
      return new Promise(resolve => {
        const id = makeID();
        requests.set(id, value => { if (typeof callback === "function") callback(value); resolve(value); });
        native.postMessage({kind: "permission", id});
      });
    }
    close() {
      if (!notifications.has(this._mailportID)) return;
      native.postMessage({kind: "close", id: this._mailportID});
      notifications.delete(this._mailportID);
      emit(this, "close");
    }
  }
  Object.defineProperty(window, "__mailportNotifications", {value: Object.freeze({
    permissionChanged(value, id) {
      if (!["default", "denied", "granted"].includes(value)) return;
      const changed = permission !== value;
      permission = value;
      if (changed) {
        permissionStatus.dispatchEvent(new Event("change"));
        if (typeof permissionStatus.onchange === "function") permissionStatus.onchange(new Event("change"));
      }
      if (requests.has(id)) { const done = requests.get(id); requests.delete(id); done(value); }
    },
    shown(id) { const item = notifications.get(id); if (item) emit(item, "show"); },
    failed(id) { const item = notifications.get(id); if (item) { emit(item, "error"); notifications.delete(id); } },
    clicked(id) { const item = notifications.get(id); if (item) { emit(item, "click"); notifications.delete(id); } }
  }), configurable: false});
  Object.defineProperty(window, "Notification", {value: MailPortNotification, configurable: true, writable: false});
})();
