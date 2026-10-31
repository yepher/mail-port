const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../Sources/MailPortEmbedded/Resources/YouTubePlayback.js'), 'utf8');
function fixture({host='www.youtube.com', frame=true, ready=true, paused=false}={}) {
  let plays=0, pauses=0, scrolls=0, blurs=0, escapes=0, covering=false;
  const window={}; window.top=frame?window:{};
  const video={readyState:ready?2:0, paused, ended:false,
    play:async()=>{plays++; video.paused=false;}, pause:()=>{pauses++;video.paused=true;}};
  const player={querySelector:()=>video, scrollIntoView:()=>scrolls++, contains:node=>node===video, getBoundingClientRect:()=>({left:100,top:80,width:640,height:360})};
  const context=vm.createContext({window, location:{protocol:'https:',hostname:host},document:{querySelector:()=>player,
    activeElement:{blur:()=>{blurs++;covering=false;}},
    dispatchEvent:event=>{if(event.key==='Escape')escapes++;},
    elementFromPoint:()=>covering?{}:video},
    KeyboardEvent:class {constructor(type,options){Object.assign(this,options);}}, setTimeout:fn=>fn(),innerWidth:1000,innerHeight:700});
  return {video, setCovering:value=>{covering=value;}, dismissal:()=>({blurs,escapes}), context, counts:()=>({plays,pauses,scrolls}), run:async action=>{context.action=action; return JSON.parse(JSON.stringify(await vm.runInContext('(async()=>{'+source+'})()',context)));}};
}
test('status does not change playback; toggle pauses then resumes the same video', async()=>{
  const f=fixture(); assert.deepEqual(await f.run('status'),{hasVideo:true,playing:true});
  assert.deepEqual(f.counts(),{plays:0,pauses:0,scrolls:0});
  assert.equal((await f.run('toggle')).playing,false);
  assert.equal((await f.run('toggle')).playing,true);
  assert.deepEqual(f.counts(),{plays:1,pauses:1,scrolls:0});
});
test('frame returns player geometry without changing playback or styling',async()=>{
  const f=fixture(); assert.deepEqual((await f.run('frame')).frame,{x:100,y:80,width:640,height:360,viewportWidth:1000,viewportHeight:700});
  assert.deepEqual(f.counts(),{plays:0,pauses:0,scrolls:1});
});
test('other origins, frames, and unready players cannot be controlled',async()=>{
  for(const options of [{host:'accounts.google.com'},{frame:false},{ready:false}]){
    const f=fixture(options); assert.deepEqual(await f.run('toggle'),{hasVideo:false}); assert.equal(f.counts().plays,0);assert.equal(f.counts().pauses,0);
  }
});
test('playback failures propagate instead of reporting success',async()=>{
  const f=fixture({paused:true}); f.video.play=async()=>{throw new Error('Playback blocked');};
  await assert.rejects(f.run('toggle'),/Playback blocked/);
  await assert.rejects(f.run('unknown'),/Unknown playback action/);
});

test('pop-out dismisses focused search suggestions without clicking or changing playback', async()=>{
  const f=fixture(); f.setCovering(true);
  assert.equal((await f.run('frame')).hasVideo,true);
  assert.deepEqual(f.dismissal(),{blurs:1,escapes:1});
  assert.equal(f.video.paused,false);
  assert.deepEqual(f.counts(),{plays:0,pauses:0,scrolls:1});
});
test('status never blurs search and an undismissed overlay prevents an obscured pop-out',async()=>{
  const f=fixture(); await f.run('status'); assert.deepEqual(f.dismissal(),{blurs:0,escapes:0});
  f.context.document.activeElement.blur=()=>{}; f.setCovering(true);
  await assert.rejects(f.run('frame'),/still covering the player/);
  assert.equal(f.video.paused,false);
});
