// Tunr webspeler: afspelen met <audio> (+ hls.js voor HLS als de browser dat niet zelf kan), Media Session API,
// slaaptimer, vorige/volgende binnen de lijst waaruit je startte, klik tellen en "Recent".
// Podcasts (SPEC §8): dezelfde speler in "afleveringmodus" (item.kind === 'episode'): spoelen, −15/+30 s,
// snelheid, positie onthouden (elke 10 s en bij pauze), slaaptimer "einde van aflevering", Media Session met seek.
// Gemengde inhoud: op een https-pagina blokkeert de browser http-streams. Volgorde van proberen:
//   1. url_resolved / url als die al https zijn;  2. dezelfde adressen met https://;  3. anders "alleen in de app".
(function () {
  var T = window.T = window.T || {};
  var HLS_SRC = 'https://cdnjs.cloudflare.com/ajax/libs/hls.js/1.5.13/hls.min.js';
  var audio = new Audio();
  audio.preload = 'none';
  audio.setAttribute('playsinline', '');
  var hls = null, hlsP = null;
  var state = 'idle';           // idle | loading | playing | paused | error | blocked
  var cur = null, queue = [], qi = -1;
  var cands = [], ci = 0, attemptTimer = null, counted = {};
  var sleepEnd = 0, sleepTimer = null, fadeTimer = null, sleepEoe = false;
  var tsubs = [], lastSave = 0, pendingSeek = null;
  function isEp(x) { return !!x && x.kind === 'episode'; }
  var subs = [];
  var secure = location.protocol === 'https:';

  function emit() { subs.forEach(function (f) { try { f(state, cur); } catch (e) { console.warn(e); } }); document.documentElement.classList.toggle('is-live', state === 'playing'); }
  function set(s) { state = s; emit(); updateSession(); }

  function isHls(u, s) { return (s && s.hls) || /\.m3u8(\?|$)/i.test(u); }
  function candidates(s) {
    var raw = [];
    (isEp(s) ? [s.url] : [s.stream, s.url]).forEach(function (u) { u = String(u || '').trim(); if (/^https?:\/\//i.test(u) && raw.indexOf(u) < 0) raw.push(u); });
    if (!secure) return raw;
    var out = [];
    raw.forEach(function (u) { if (/^https:/i.test(u)) out.push(u); });
    raw.forEach(function (u) { if (/^http:/i.test(u)) { var v = u.replace(/^http:/i, 'https:'); if (out.indexOf(v) < 0) out.push(v); } });
    return out;
  }
  function hadHttpOnly(s) { if (isEp(s)) return secure && /^http:/i.test(s.url || ''); return secure && [s.stream, s.url].some(function (u) { return /^http:/i.test(u || ''); }) && ![s.stream, s.url].some(function (u) { return /^https:/i.test(u || ''); }); }

  function loadHls() {
    if (window.Hls) return Promise.resolve(window.Hls);
    if (hlsP) return hlsP;
    hlsP = new Promise(function (res, rej) {
      var sc = document.createElement('script');
      sc.src = HLS_SRC; sc.async = true; sc.crossOrigin = 'anonymous';
      sc.onload = function () { window.Hls ? res(window.Hls) : rej(new Error('hls')); };
      sc.onerror = function () { hlsP = null; rej(new Error('hls')); };
      document.head.appendChild(sc);
    });
    return hlsP;
  }
  function teardown() {
    clearTimeout(attemptTimer);
    if (hls) { try { hls.destroy(); } catch (e) {} hls = null; }
    audio.removeAttribute('src');
    try { audio.load(); } catch (e) {}
  }

  function attempt() {
    clearTimeout(attemptTimer);
    if (isEp(cur)) { attemptEp(); return; }
    if (ci >= cands.length) {
      teardown();
      // alleen http-adressen en de https-variant werkte ook niet → de browser blokkeert hem; anders echt onbereikbaar
      set(cur && hadHttpOnly(cur) ? 'blocked' : 'error');
      return;
    }
    var u = cands[ci];
    if (hls) { try { hls.destroy(); } catch (e) {} hls = null; }
    var native = audio.canPlayType('application/vnd.apple.mpegurl');
    attemptTimer = setTimeout(next, 15000); // geen geluid binnen 15 s → volgende kandidaat
    if (isHls(u, cur) && !native) {
      loadHls().then(function (Hls) {
        if (!Hls.isSupported()) throw new Error('nohls');
        hls = new Hls({ lowLatencyMode: false, enableWorker: true });
        hls.on(Hls.Events.ERROR, function (ev, data) { if (data && data.fatal) next(); });
        hls.loadSource(u);
        hls.attachMedia(audio);
        hls.on(Hls.Events.MANIFEST_PARSED, function () { playNow(); });
      }).catch(function () { next(); });
    } else {
      audio.src = u;
      playNow();
    }
  }
  function next() { ci++; attempt(); }
  // aflevering: gewoon bestand, geen hls; geen 15 s-timer (grote bestanden mogen even laden)
  function attemptEp() {
    if (ci >= cands.length) { teardown(); set(cur && hadHttpOnly(cur) ? 'blocked' : 'error'); return; }
    audio.src = cands[ci];
    audio.playbackRate = T.store.podRate;
    attemptTimer = setTimeout(function () { if (state === 'loading' && audio.readyState < 2) next(); }, 30000);
    playNow();
  }
  function playNow() {
    var p = audio.play();
    if (p && p.catch) p.catch(function (e) {
      if (e && e.name === 'NotAllowedError') { clearTimeout(attemptTimer); set('paused'); }
      else if (e && e.name !== 'AbortError') next();
    });
  }

  audio.addEventListener('playing', function () {
    clearTimeout(attemptTimer);
    setTimeout(function () { if (state === 'playing') endedRetry = 0; }, 5000);
    if (cur && !isEp(cur) && !counted[cur.id]) { counted[cur.id] = 1; T.api.click(cur.id); }
    if (isEp(cur)) audio.playbackRate = T.store.podRate;
    set('playing');
  });
  // live stream ended (server dropped the connection): reconnect once, otherwise show the error
  var endedRetry = 0;
  audio.addEventListener('ended', function () {
    if (!cur) return;
    if (isEp(cur)) {
      savePos(true);
      set('paused');
      if (sleepEoe) { sleepEoe = false; emit(); if (T.ui) T.ui.toast(T.t('sleep.eoe.done')); }
      tick();
      return;
    }
    if (endedRetry++ < 1) { var s = cur; cur = null; play(s, queue); }
    else { teardown(); set('error'); }
  });
  audio.addEventListener('waiting', function () { if (state === 'playing') set('loading'); });
  audio.addEventListener('pause', function () {
    if (isEp(cur)) savePos();
    if (state === 'playing' || state === 'loading') { if (!audio.src && !hls) return; if (isEp(cur) && audio.ended) return; set('paused'); }
  });
  // positie: bewaren elke 10 s (en bij pauze/einde); voortgang naar de UI en de Media Session
  function savePos(end) {
    if (!isEp(cur)) return;
    var d = audio.duration && isFinite(audio.duration) ? audio.duration : (cur.dur || 0);
    if (!d) return;
    T.store.savePos(cur, end ? d : audio.currentTime, d);
    lastSave = Date.now();
  }
  var lastPS = 0;
  function tick() {
    if (!isEp(cur)) return;
    tsubs.forEach(function (f) { try { f(); } catch (e) { console.warn(e); } });
    if (Date.now() - lastPS > 1000) { lastPS = Date.now(); positionState(); }
  }
  audio.addEventListener('timeupdate', function () {
    if (!isEp(cur)) return;
    if (state === 'playing' && Date.now() - lastSave > 10000 && audio.currentTime > 1) savePos();
    tick();
  });
  audio.addEventListener('loadedmetadata', function () {
    if (!isEp(cur)) return;
    if (pendingSeek != null && isFinite(audio.duration)) { try { audio.currentTime = Math.min(pendingSeek, Math.max(0, audio.duration - 2)); } catch (e) {} }
    pendingSeek = null;
    tick(); positionState();
  });
  audio.addEventListener('ratechange', function () { if (isEp(cur)) { positionState(); emit(); } });
  audio.addEventListener('seeked', function () { if (isEp(cur)) { savePos(); tick(); positionState(); } });
  audio.addEventListener('error', function () { if (state === 'loading' || state === 'playing') next(); });
  audio.addEventListener('stalled', function () { /* laat de timer beslissen */ });
  audio.volume = T.store.volume;

  function play(s, list) {
    if (!s) return;
    if (cur && cur.id === s.id && (state === 'playing' || state === 'loading')) return;
    teardown();
    cur = s;
    if (list && list.length) { queue = list.slice(); qi = queue.findIndex(function (x) { return x.id === s.id; }); if (qi < 0) { queue.unshift(s); qi = 0; } }
    else if (queue.findIndex(function (x) { return x.id === s.id; }) < 0) { queue = [s]; qi = 0; }
    else qi = queue.findIndex(function (x) { return x.id === s.id; });
    if (isEp(s)) {
      var saved = T.store.pos(s.id);
      pendingSeek = saved && !saved.done && saved.t > 3 ? saved.t : null;
      if (sleepEoe) sleepEoe = false;
    } else {
      T.store.addRecent(s);
      if (sleepEoe) sleepEoe = false;
    }
    cands = candidates(s); ci = 0;
    audio.volume = T.store.volume;
    set('loading');
    if (!cands.length) { set(hadHttpOnly(s) ? 'blocked' : 'error'); return; }
    attempt();
  }
  function resume() {
    if (!cur) return;
    // aflevering: verder waar hij was (de buffer is geen oude live-audio)
    if (isEp(cur) && audio.src && state !== 'error' && state !== 'blocked') {
      if (audio.ended) { try { audio.currentTime = 0; } catch (e) {} }
      set('loading'); playNow(); return;
    }
    // live radio: opnieuw verbinden in plaats van een oude buffer af te spelen
    var keep = cur; cur = null; play(keep, queue);
  }
  function pause() {
    if (!cur) return; clearTimeout(attemptTimer);
    if (isEp(cur)) { audio.pause(); savePos(); set('paused'); return; }
    audio.pause(); teardown(); set('paused');
  }
  function seek(sec) {
    if (!isEp(cur)) return;
    var d = audio.duration && isFinite(audio.duration) ? audio.duration : (cur.dur || 0);
    sec = Math.max(0, d ? Math.min(sec, d - 0.5) : sec);
    if (audio.readyState >= 1) { try { audio.currentTime = sec; } catch (e) {} } else pendingSeek = sec;
    tick();
  }
  function skip(d) { if (isEp(cur)) seek(curTime() + d); }
  function curTime() { return audio.readyState >= 1 ? audio.currentTime : (pendingSeek != null ? pendingSeek : ((T.store.pos(cur && cur.id) || {}).t || 0)); }
  function duration() { return audio.duration && isFinite(audio.duration) ? audio.duration : ((cur && cur.dur) || 0); }
  function setRate(r) { T.store.podRate = r; audio.playbackRate = r; emit(); }
  function toggle() { if (state === 'playing' || state === 'loading') pause(); else resume(); }
  function step(d) {
    if (!queue.length) return;
    var i = (qi + d + queue.length) % queue.length;
    play(queue[i], queue);
  }

  // ---------- slaaptimer ----------
  function setSleep(min) {
    clearTimeout(sleepTimer); clearInterval(fadeTimer);
    audio.volume = T.store.volume;
    sleepEoe = false;
    if (min === 'eoe') { sleepEnd = 0; sleepEoe = true; emit(); return; }
    if (!min) { sleepEnd = 0; emit(); return; }
    sleepEnd = Date.now() + min * 60000;
    var fadeMs = 10000;
    sleepTimer = setTimeout(function () {
      var v0 = audio.volume, t0 = Date.now();
      fadeTimer = setInterval(function () {
        var k = (Date.now() - t0) / fadeMs;
        if (k >= 1) { clearInterval(fadeTimer); pause(); audio.volume = T.store.volume; sleepEnd = 0; emit(); if (T.ui) T.ui.toast(T.t('sleep.done')); return; }
        audio.volume = Math.max(0, v0 * (1 - k));
      }, 200);
    }, Math.max(0, min * 60000 - fadeMs));
    emit();
  }

  // ---------- Media Session ----------
  function updateSession() {
    if (!('mediaSession' in navigator) || !cur) return;
    try {
      var art = T.logoUrl(cur.favicon);
      var base = new URL('../assets/img/', location.href).href;
      if (isEp(cur)) {
        var pa = T.logoUrl(cur.art);
        navigator.mediaSession.metadata = new MediaMetadata({
          title: cur.title, artist: cur.pname || '', album: 'Tunr · ' + T.t('pod.title'),
          artwork: (pa ? [{ src: pa, sizes: '600x600' }] : []).concat([{ src: base + 'icon-512.png', sizes: '512x512', type: 'image/png' }])
        });
        navigator.mediaSession.playbackState = state === 'playing' || state === 'loading' ? 'playing' : 'paused';
        epHandlers(true);
        positionState();
        return;
      }
      epHandlers(false);
      navigator.mediaSession.metadata = new MediaMetadata({
        title: cur.name,
        artist: [T.tagsLine(cur, 2), T.countryName(cur.cc, cur.country)].filter(Boolean).join(' · '),
        album: 'Tunr · ' + T.t('player.live'),
        artwork: (art ? [{ src: art, sizes: '512x512' }] : []).concat([{ src: base + 'icon-192.png', sizes: '192x192', type: 'image/png' }, { src: base + 'icon-512.png', sizes: '512x512', type: 'image/png' }])
      });
      navigator.mediaSession.playbackState = state === 'playing' || state === 'loading' ? 'playing' : 'paused';
    } catch (e) {}
  }
  var msH = function (a, f) { try { navigator.mediaSession.setActionHandler(a, f); } catch (e) {} };
  var epOn = null;
  function epHandlers(on) {
    if (!('mediaSession' in navigator) || epOn === on) return;
    epOn = on;
    msH('seekbackward', on ? function (d) { skip(-((d && d.seekOffset) || 15)); } : null);
    msH('seekforward', on ? function (d) { skip((d && d.seekOffset) || 30); } : null);
    msH('seekto', on ? function (d) { if (d && d.seekTime != null) { if (d.fastSeek && 'fastSeek' in audio) audio.fastSeek(d.seekTime); else seek(d.seekTime); } } : null);
    if (!on) { try { navigator.mediaSession.setPositionState(); } catch (e) {} }
  }
  function positionState() {
    if (!('mediaSession' in navigator) || !isEp(cur) || !navigator.mediaSession.setPositionState) return;
    var d = duration();
    if (!d || !isFinite(d)) return;
    try { navigator.mediaSession.setPositionState({ duration: d, playbackRate: audio.playbackRate || 1, position: Math.min(d, Math.max(0, curTime())) }); } catch (e) {}
  }
  if ('mediaSession' in navigator) {
    var h = msH;
    h('play', resume); h('pause', pause); h('stop', pause);
    h('previoustrack', function () { step(-1); }); h('nexttrack', function () { step(1); });
  }

  T.player = {
    on: function (f) { subs.push(f); },
    play: play, pause: pause, toggle: toggle, resume: resume,
    prev: function () { step(-1); }, next: function () { step(1); },
    retry: function () { if (cur) { var s = cur; cur = null; play(s, queue); } },
    get state() { return state; }, get current() { return cur; }, get queue() { return queue; },
    isCurrent: function (id) { return !!cur && cur.id === id; },
    isActive: function (id) { return !!cur && cur.id === id && (state === 'playing' || state === 'loading'); },
    setVolume: function (v) { audio.volume = v; T.store.volume = v; },
    get volume() { return audio.volume; },
    setSleep: setSleep, get sleepEnd() { return sleepEnd; }, get sleepEoe() { return sleepEoe; },
    // afleveringen
    get isEpisode() { return isEp(cur); },
    onTime: function (f) { tsubs.push(f); },
    seek: seek, skip: skip, setRate: setRate,
    get time() { return cur ? curTime() : 0; }, get duration() { return duration(); },
    get rate() { return T.store.podRate; }
  };
  // bij het sluiten van de pagina de positie bewaren
  window.addEventListener('pagehide', function () { if (isEp(cur) && state === 'playing') savePos(); });
})();
