// Explicit playback actions only; status checks never change playback.
if (location.protocol !== 'https:' || location.hostname !== 'www.youtube.com' || window.top !== window) return {hasVideo: false};
const player = document.querySelector('#movie_player');
const video = player && player.querySelector('video');
if (!video || video.readyState < 1) return {hasVideo: false};
if (action === 'toggle') {
  if (video.paused || video.ended) await video.play();
  else video.pause();
} else if (action === 'frame') {
  // Search suggestions and page menus otherwise travel with the cropped web view.
  // Blur the actual field too, so reparenting cannot reopen its suggestions.
  const focused = document.activeElement;
  if (focused && typeof focused.blur === 'function') focused.blur();
  document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', code: 'Escape', keyCode: 27, which: 27, bubbles: true}));
  await new Promise(resolve => setTimeout(resolve, 80));
  player.scrollIntoView({block: 'nearest', inline: 'nearest', behavior: 'instant'});
} else if (action !== 'status') throw new Error('Unknown playback action.');
const state = {hasVideo: true, playing: !video.paused && !video.ended};
if (action === 'frame') {
  const rect = player.getBoundingClientRect();
  for (const fraction of [0.25, 0.5, 0.75]) {
    const top = document.elementFromPoint(rect.left + rect.width * fraction, rect.top + rect.height * 0.5);
    if (top && !player.contains(top)) throw new Error('A YouTube menu is still covering the player. Press Escape in YouTube and try Pop Out Video again.');
  }
  state.frame = {x: rect.left, y: rect.top, width: rect.width, height: rect.height, viewportWidth: innerWidth, viewportHeight: innerHeight};
}
return state;
