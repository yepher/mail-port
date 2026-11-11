// MailPort mobile YouTube ad skipping: opt-in, visible Skip controls only.
(() => {
  const previous = globalThis.__mailportMobileAdSkip;
  if (previous) clearInterval(previous.timer);
  const state = globalThis.__mailportMobileAdSkip = { timer: null };
  if (!/*__MAILPORT_SKIP_ENABLED__*/false || location.protocol !== 'https:' ||
      !['www.youtube.com', 'm.youtube.com'].includes(location.hostname) || window.top !== window) return;
  const skip = () => {
    const player = document.querySelector('#movie_player, .html5-video-player, #player');
    if (!player) return;
    const buttons = player.querySelectorAll('.ytp-skip-ad-button, .ytp-ad-skip-button, .ytp-ad-skip-button-modern, .ytp-ad-skip-button-container button, .ytp-ad-skip-button-slot button, .ytm-ad-player-overlay-skip-button');
    for (const button of buttons) {
      if (button.disabled || button.getAttribute('aria-disabled') === 'true' ||
          button.closest('[hidden], [aria-hidden="true"]') || !button.getClientRects().length) continue;
      const style = getComputedStyle(button);
      if (style.visibility !== 'visible' || style.display === 'none' || Number(style.opacity) === 0) continue;
      const rect = button.getBoundingClientRect();
      const x = rect.left + rect.width / 2, y = rect.top + rect.height / 2;
      if (x < 0 || y < 0 || x >= innerWidth || y >= innerHeight || !button.contains(document.elementFromPoint(x, y))) continue;
      // Public WebKit APIs cannot generate a trusted touch. Some YouTube players
      // accept this activation; others still require the user to tap Skip.
      button.click();
      break;
    }
  };
  state.timer = setInterval(skip, 500);
  skip();
})();
