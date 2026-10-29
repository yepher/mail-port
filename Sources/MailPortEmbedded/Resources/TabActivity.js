(() => {
  "use strict";
  const months = "January February March April May June July August September October November December".split(" ");
  const datePattern = new RegExp("(" + months.join("|") + ")\\s+(\\d{1,2})(?:\\s*[–-]\\s*(\\d{1,2}))?,\\s*(\\d{4})", "i");
  function unreadNumber(text) {
    if (typeof text !== "string" || !/^[\d,\s\u00a0]+$/.test(text.trim())) return null;
    const value = Number(text.replace(/[,\s\u00a0]/g, ""));
    return Number.isInteger(value) && value >= 0 && value <= 1000000 ? value : null;
  }
  function inboxTitle(title) {
    const match = /^Inbox\s*\(([\d,\s\u00a0]+)\)/i.exec(title);
    return match ? unreadNumber(match[1]) : (/^Inbox(?:\s*[-–—]|$)/i.test(title) ? 0 : null);
  }
  function eventWindow(label, offsetMinutes = null) {
    if (typeof label !== "string" || label.length > 3000 || /^\s*All day\b/i.test(label) || /,\s*Declined\b/i.test(label)) return null;
    const time = /^\s*(\d{1,2})(?::(\d{2}))?\s*([ap]\.?m\.?)?\s*(?:to|[–—-])\s*(\d{1,2})(?::(\d{2}))?\s*([ap]\.?m\.?)?\s*,/i.exec(label);
    const date = Array.from(label.matchAll(new RegExp(datePattern.source, "ig"))).at(-1);
    if (!time || !date || (!time[3] && !time[6] && (!time[2] || !time[5]))) return null;
    let sh = Number(time[1]), eh = Number(time[4]);
    const sm = Number(time[2] || 0), em = Number(time[5] || 0);
    const meridiem = value => value?.toLowerCase().replace(/\./g, "");
    let sa = meridiem(time[3]), ea = meridiem(time[6]);
    if (sm > 59 || em > 59 || sh > 23 || eh > 23) return null;
    if (sa || ea) {
      if (sh < 1 || sh > 12 || eh < 1 || eh > 12) return null;
      const convert = (h, a) => h % 12 + (a === "pm" ? 12 : 0);
      sa ||= ea; ea ||= sa;
      sh = convert(sh, sa); eh = convert(eh, ea);
      if (!time[3] && sh > eh) sh = (sh + 12) % 24;
    }
    const month = months.findIndex(m => m.toLowerCase() === date[1].toLowerCase());
    const day = Number(date[2]), year = Number(date[4]);
    if (year < 2000 || year > 2200 || day < 1 || day > 31) return null;
    const localStart = new Date(year, month, day, sh, sm);
    if (localStart.getMonth() !== month || localStart.getDate() !== day) return null;
    const makeDate = (d, h, m) => offsetMinutes === null ? new Date(year, month, d, h, m) : new Date(Date.UTC(year, month, d, h, m) - offsetMinutes * 60000);
    const start = makeDate(day, sh, sm);
    let end = makeDate(Number(date[3] || date[2]), eh, em);
    if (end < start && !date[3]) end = makeDate(day + 1, eh, em);
    if (end - start <= 0 || end - start > 14 * 86400000) return null;
    return {start: start.getTime(), end: end.getTime()};
  }
  if (typeof module !== "undefined" && module.exports) { module.exports = {unreadNumber, inboxTitle, eventWindow}; return; }
  if (location.protocol !== "https:" || window.top !== window || !["mail.google.com", "calendar.google.com"].includes(location.hostname)) return;
  const native = window.webkit?.messageHandlers?.mailPortActivity;
  if (!native) return;
  function accessibleText(node) {
    const refs = (node.getAttribute("aria-labelledby") || "").split(/\s+/).filter(Boolean);
    return [node.getAttribute("aria-label"), ...refs.map(id => document.getElementById(id)?.textContent), node.innerText].filter(Boolean);
  }
  function readUnread() {
    const link = document.querySelector('a[href$="#inbox"], a[href*="#inbox/"]');
    if (link) {
      const row = link.closest('.aim, [role="treeitem"]') || link.parentElement?.parentElement;
      const counter = row?.querySelector('.bsU');
      if (counter) {
        const count = unreadNumber(counter.textContent.trim());
        if (count !== null) return count;
      }
      const text = [row?.getAttribute("aria-label"), link.getAttribute("aria-label"), row?.innerText].filter(Boolean).join(" ");
      const match = /([\d,\s\u00a0]+)\s+unread\b/i.exec(text) || /\bInbox\s*\(?([\d,\u00a0]+)\)?\s*$/i.exec(text);
      if (match) { const count = unreadNumber(match[1]); if (count !== null) return count; }
      const title = inboxTitle(document.title);
      if (title !== null) return title;
      if (/\bInbox\b/i.test(link.textContent)) return 0;
    }
    return inboxTitle(document.title);
  }
  function readEvents() {
    const result = new Map();
    const zone = /(?:^|\n)GMT\s*([+−-])(\d{1,2})(?::(\d{2}))?\s*(?:\n|$)/.exec(document.body?.innerText || "");
    const offset = zone ? (zone[1] === "+" ? 1 : -1) * (Number(zone[2]) * 60 + Number(zone[3] || 0)) : null;
    const nodes = document.querySelectorAll('[data-eventid], [role="button"][aria-label], [role="gridcell"][aria-label]');
    for (const node of Array.from(nodes).slice(0, 3000)) {
      for (const label of accessibleText(node)) {
        const item = eventWindow(label, offset);
        if (item) result.set(item.start + "/" + item.end, item);
      }
    }
    return Array.from(result.values()).slice(0,1000);
  }
  function scan() {
    if (location.hostname === "mail.google.com") {
      const count = readUnread();
      if (count !== null) native.postMessage({kind:"unread",count});
    } else if (/Calendar/.test(document.title)) {
      native.postMessage({kind:"calendar",events:readEvents()});
    }
  }
  let queued;
  const observer = new MutationObserver(() => { clearTimeout(queued); queued = setTimeout(scan, 500); });
  observer.observe(document.documentElement, {subtree:true,childList:true,characterData:true,attributes:true,attributeFilter:["aria-label","aria-labelledby","data-eventid"]});
  setInterval(scan, 30000);
  document.addEventListener("visibilitychange", scan);
  scan();
})();
