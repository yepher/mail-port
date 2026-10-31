// MailPort YouTube ad skipping: opt-in, available Skip controls only.
(() => {
  if (location.protocol !== 'https:' || location.hostname !== 'www.youtube.com' || window.top !== window) return;
  if (globalThis.__mailportSkipTimer) clearInterval(globalThis.__mailportSkipTimer);
  globalThis.__mailportSkipEnabled = /*__MAILPORT_SKIP_ENABLED__*/false;
  const visible = (button) => {
    if (button.disabled || button.getAttribute('aria-disabled') === 'true' ||
        button.closest('[hidden], [aria-hidden="true"]') || !button.getClientRects().length) return false;
    const style = getComputedStyle(button);
    return style.visibility !== 'hidden' && style.visibility !== 'collapse' && style.display !== 'none';
  };
  const skip = () => {
    if (!globalThis.__mailportSkipEnabled) return;
    // Don't depend on ad-showing: YouTube varies player classes and may leave a
    // hidden old Skip button before the live one. Check every known Skip control.
    const player = document.querySelector('#movie_player') || document.querySelector('.html5-video-player');
    if (!player) return;
    const buttons = player.querySelectorAll('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button-container button, .ytp-ad-skip-button-slot button');
    const button = Array.from(buttons).find(visible);
    if (!button) return null;
    const rect = button.getBoundingClientRect();
    const x = rect.left + rect.width / 2, y = rect.top + rect.height / 2;
    if (x < 0 || y < 0 || x >= innerWidth || y >= innerHeight || !button.contains(document.elementFromPoint(x, y))) return null;
    // Return geometry only. Native input is needed: YouTube can ignore synthetic clicks.
    return { x, y, width: innerWidth, height: innerHeight };
  };
  // Native scheduling avoids relying on a page timer remaining active.
  globalThis.__mailportSkipNow = skip;
  return skip();
})();
