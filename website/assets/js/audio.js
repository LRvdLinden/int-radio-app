// Tunr webspeler: afspelen met <audio> (+ hls.js voor HLS als de browser dat niet zelf kan), Media Session API,
// slaaptimer, vorige/volgende binnen de lijst waaruit je startte, klik tellen en "Recent".
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
  var sleepEnd = 0, sleepTimer = null, fadeTimer = null;
  var subs = [];
  var secure = location.protocol === 'https:';

  function emit() { subs.forEach(function (f) { try { f(state, cur); } catch (e) { console.warn(e); } }); document.documentElement.classList.toggle('is-live', state === 'playing'); }
  function set(s) { state = s; emit(); updateSession(); }

  function isHls(u, s) { return (s && s.hls) || /\.m3u8(\?|$)/i.test(u); }
  function candidates(s) {
    var raw = [];
    [s.stream, s.url].forEach(function (u) { u = String(u || '').trim(); if (/^https?:\/\//i.test(u) && raw.indexOf(u) < 0) raw.push(u); });
    if (!secure) return raw;
    var out = [];
    raw.forEach(function (u) { if (/^https:/i.test(u)) out.push(u); });
    raw.forEach(function (u) { if (/^http:/i.test(u)) { var v = u.replace(/^http:/i, 'https:'); if (out.indexOf(v) < 0) out.push(v); } });
    return out;
  }
  function hadHttpOnly(s) { return secure && [s.stream, s.url].some(function (u) { return /^http:/i.test(u || ''); }) && ![s.stream, s.url].some(function (u) { return /^https:/i.test(u || ''); }); }

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
    if (cur && !counted[cur.id]) { counted[cur.id] = 1; T.api.click(cur.id); }
    set('playing');
  });
  // live stream ended (server dropped the connection): reconnect once, otherwise show the error
  var endedRetry = 0;
  audio.addEventListener('ended', function () {
    if (!cur) return;
    if (endedRetry++ < 1) { var s = cur; cur = null; play(s, queue); }
    else { teardown(); set('error'); }
  });
  audio.addEventListener('waiting', function () { if (state === 'playing') set('loading'); });
  audio.addEventListener('pause', function () { if (state === 'playing' || state === 'loading') { if (!audio.src && !hls) return; set('paused'); } });
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
    T.store.addRecent(s);
    cands = candidates(s); ci = 0;
    audio.volume = T.store.volume;
    set('loading');
    if (!cands.length) { set(hadHttpOnly(s) ? 'blocked' : 'error'); return; }
    attempt();
  }
  function resume() {
    if (!cur) return;
    // live radio: opnieuw verbinden in plaats van een oude buffer af te spelen
    var keep = cur; cur = null; play(keep, queue);
  }
  function pause() { if (!cur) return; clearTimeout(attemptTimer); audio.pause(); teardown(); set('paused'); }
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
      navigator.mediaSession.metadata = new MediaMetadata({
        title: cur.name,
        artist: [T.tagsLine(cur, 2), T.countryName(cur.cc, cur.country)].filter(Boolean).join(' · '),
        album: 'Tunr · ' + T.t('player.live'),
        artwork: (art ? [{ src: art, sizes: '512x512' }] : []).concat([{ src: base + 'icon-192.png', sizes: '192x192', type: 'image/png' }, { src: base + 'icon-512.png', sizes: '512x512', type: 'image/png' }])
      });
      navigator.mediaSession.playbackState = state === 'playing' || state === 'loading' ? 'playing' : 'paused';
    } catch (e) {}
  }
  if ('mediaSession' in navigator) {
    var h = function (a, f) { try { navigator.mediaSession.setActionHandler(a, f); } catch (e) {} };
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
    setSleep: setSleep, get sleepEnd() { return sleepEnd; }
  };
})();
