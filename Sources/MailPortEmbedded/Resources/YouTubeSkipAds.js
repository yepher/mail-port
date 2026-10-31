// Opt-in: only press the Skip button once YouTube makes it available.
(() => {
  if (location.protocol !== 'https:' || location.hostname !== 'www.youtube.com' || window.top !== window) return;
  if (globalThis.__mailportSkipTimer) clearInterval(globalThis.__mailportSkipTimer);
  globalThis.__mailportSkipEnabled = false;
  globalThis.__mailportSkipTimer = setInterval(() => {
    if (!globalThis.__mailportSkipEnabled) return;
    const player = document.querySelector('#movie_player.ad-showing');
    if (!player) return;
    const button = player.querySelector('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern');
    if (button && !button.disabled && button.getClientRects().length) button.click();
  }, 750);
})();
