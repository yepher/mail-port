// Runs only when the user asks to save a transcript, in the page's own world because
// YouTube's caption list lives on its player. Same approach as the Docent extension.
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const clean = (text) => String(text || '').replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
const clock = (seconds) => {
  const whole = Math.floor(seconds), hours = Math.floor(whole / 3600), minutes = Math.floor(whole / 60) % 60, rest = String(whole % 60).padStart(2, '0');
  return hours ? `${hours}:${String(minutes).padStart(2, '0')}:${rest}` : `${minutes}:${rest}`;
};

// About half a minute of speech per block. Rolling captions repeat the previous line.
const group = (cues) => {
  const blocks = [];
  let current = null, previous = '';
  for (const cue of cues) {
    if (!cue.text || cue.text === previous) continue;
    previous = cue.text;
    if (!current || current.text.length >= 320 || cue.t - current.t >= 40) {
      current = { t: cue.t, text: cue.text };
      blocks.push(current);
    } else current.text += ` ${cue.text}`;
  }
  return blocks.map((block) => ({ time: clock(block.t), text: block.text }));
};

const player = document.querySelector('#movie_player, .html5-video-player');
const response = player && player.getPlayerResponse && player.getPlayerResponse();
if (!response || !response.videoDetails) return { segments: [] };
const title = response.videoDetails.title || '';
const duration = Number(response.videoDetails.lengthSeconds) || 0;
const list = response.captions && response.captions.playerCaptionsTracklistRenderer;
const tracks = (list && list.captionTracks) || [];
if (!tracks.length) return { title, duration, segments: [] };

// Your language first, then English, then anything; written captions before automatic ones.
const language = (code) => String(code || '').toLowerCase().split('-')[0];
const want = language(navigator.language) || 'en';
const rank = (track) => (language(track.languageCode) === want ? 0 : language(track.languageCode) === 'en' ? 2 : 4) + (track.kind === 'asr' ? 1 : 0);
const track = [...tracks].sort((a, b) => rank(a) - rank(b))[0];

const load = async (address) => {
  try {
    const url = new URL(address, location.href);
    url.searchParams.set('fmt', 'json3');
    const reply = await fetch(url.href);
    const body = reply.ok ? await reply.text() : '';
    return body ? JSON.parse(body) : null;
  } catch (_) { return null; }
};

let captions = await load(track.baseUrl);
if (!captions || !captions.events) {
  // YouTube can require the player's own token, so borrow it from the request the
  // player makes when subtitles turn on, then put subtitles back as they were.
  const videoID = response.videoDetails.videoId;
  const playerRequest = () => performance.getEntriesByType('resource').map((entry) => entry.name)
    .filter((name) => name.includes('/api/timedtext') && /[?&]pot=/.test(name) && name.includes(`v=${videoID}`)).pop();
  let seen = playerRequest();
  if (!seen && player.toggleSubtitlesOn) {
    const wasOn = player.isSubtitlesOn && player.isSubtitlesOn();
    // The player asks for captions only once the video itself is playing, so an
    // ad holds this up. Keep asking for a while rather than giving up.
    for (let attempt = 0; attempt < 180 && !(seen = playerRequest()); attempt += 1) {
      if (attempt % 20 === 0) {
        if (player.toggleSubtitlesOff) player.toggleSubtitlesOff();
        player.toggleSubtitlesOn();
      }
      await sleep(250);
    }
    if (!wasOn && player.toggleSubtitlesOff) player.toggleSubtitlesOff();
  }
  if (seen) {
    const from = new URL(seen), to = new URL(track.baseUrl, location.href);
    for (const [key, value] of from.searchParams) {
      if (!to.searchParams.has(key) && !['kind', 'tlang', 'name', 'lang', 'fmt'].includes(key)) to.searchParams.set(key, value);
    }
    captions = await load(to.href);
  }
}
if (!captions || !captions.events) return { title, duration, segments: [] };

const cues = captions.events.filter((event) => event.segs)
  .map((event) => ({ t: (event.tStartMs || 0) / 1000, text: clean(event.segs.map((segment) => segment.utf8 || '').join('')) }));
return { title, duration, segments: group(cues) };
