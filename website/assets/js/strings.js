// Tunr webspeler: teksten (NL/EN, zelfde als de apps) en kleine hulpjes (vlag, landnaam, getallen, StationArt).
(function () {
  var T = window.T = window.T || {};
  var S = {
    nl: {
      'tap.title': 'Alle radio van de wereld', 'tap.sub': 'Tik om af te stemmen', 'tap.btn': 'Start', 'tap.hint': 'Met geluid · overslaan met een tik',
      'splash.skip': 'Overslaan',
      'tab.discover': 'Ontdek', 'tab.browse': 'Bladeren', 'tab.map': 'Kaart', 'tab.search': 'Zoeken', 'tab.library': 'Bibliotheek', 'tab.settings': 'Instellingen',
      'greet.morning': 'Goedemorgen', 'greet.afternoon': 'Goedemiddag', 'greet.evening': 'Goedenavond', 'greet.night': 'Goedenacht',
      'country.title': 'Kies je land', 'country.sub': 'Je kunt dit later altijd wijzigen', 'country.search': 'Zoek een land', 'country.suggested': 'Voorgesteld', 'country.all': 'Alle landen', 'country.none': 'Geen land gevonden',
      'stations': '{n} zenders', 'station1': '1 zender',
      'row.continue': 'Verder luisteren', 'row.local': 'Lokaal', 'row.popular': 'Populair in {c}', 'row.trending': 'Trending', 'row.favorites': 'Jouw favorieten', 'row.genres': 'Genres', 'row.genre': '{g} in {c}',
      'all': 'Alles', 'listen': 'Luister', 'info': 'Info', 'play': 'Afspelen', 'pause': 'Pauze', 'stop': 'Stop', 'retry': 'Opnieuw', 'back': 'Terug', 'close': 'Sluiten', 'more': 'Meer',
      'local.pick': 'Kies je regio', 'local.pick.sub': 'Zenders uit je eigen provincie of staat, voortaan hier op Ontdek.', 'local.make': 'Maak dit mijn regio', 'local.is': 'Jouw regio', 'local.regions': 'Regio\'s in {c}', 'local.none': 'Geen regio\'s gevonden voor dit land.', 'local.filter': 'Zoek een regio',
      'browse.local': 'Lokaal', 'browse.music': 'Muziek', 'browse.news': 'Nieuws & Talk', 'browse.sports': 'Sport', 'browse.lang': 'Op taal', 'browse.map': 'Wereldkaart', 'browse.top': 'Top 100 wereldwijd',
      'browse.local.sub': 'Je provincie of staat', 'browse.music.sub': 'Van pop tot klassiek', 'browse.news.sub': 'Nieuws, praat en debat', 'browse.sports.sub': 'Live verslag', 'browse.lang.sub': 'Radio in elke taal', 'browse.map.sub': 'Draai de wereld rond', 'browse.top.sub': 'Meest beluisterd',
      'news.news': 'Nieuws', 'news.talk': 'Talk',
      'g.pop': 'Pop', 'g.news': 'Nieuws', 'g.rock': 'Rock', 'g.dance': 'Dance', 'g.jazz': 'Jazz', 'g.classical': 'Klassiek', 'g.hits': 'Hits', 'g.talk': 'Talk', 'g.sports': 'Sport', 'g.oldies': 'Oldies', 'g.hiphop': 'Hiphop', 'g.country': 'Country', 'g.ambient': 'Ambient', 'g.christian': 'Christelijk',
      'genre.world': 'Weinig zenders in {c}, daarom wereldwijd.',
      'map.world': 'Wereld', 'map.country': '{c}', 'map.random': 'Willekeurig', 'map.loading': 'Kaart laden…', 'map.fail.t': 'De kaart kan nu niet worden geladen', 'map.fail.p': 'Controleer je verbinding of een blokkering van externe scripts. Bladeren en Zoeken werken gewoon.', 'map.count': '{n} zenders op de kaart', 'map.none': 'Geen zenders met een locatie in dit land. Probeer Wereld.', 'map.near': 'In de buurt',
      'map.count1': '1 zender op de kaart', 'map.s.ph': 'Zoek een land of plaats', 'map.s.label': 'Zoek op de kaart een land of plaats', 'map.s.clear': 'Zoekveld wissen', 'map.s.countries': 'Landen', 'map.s.places': 'Plaatsen', 'map.s.recent': 'Recent gezocht', 'map.s.none': 'Niets gevonden voor “{q}”', 'map.s.busy': 'Plaatsen zoeken…', 'map.s.around': '{n} zenders rond {p}', 'map.s.around1': '1 zender rond {p}', 'map.s.empty': 'Geen zenders met een locatie gevonden rond {p}', 'map.s.country': 'Land',
      'detail.website': 'Website', 'detail.share': 'Delen', 'detail.fav': 'Favoriet', 'detail.similar': 'Vergelijkbare zenders', 'detail.codec': 'Codec', 'detail.bitrate': 'Bitrate', 'detail.lang': 'Taal', 'detail.votes': 'Stemmen', 'detail.clicks': 'Luisteraars', 'detail.hls': 'HLS', 'yes': 'ja', 'no': 'nee', 'kbps': '{n} kbps', 'detail.nf': 'Deze zender is niet gevonden.', 'detail.np': 'Nu aan het spelen',
      'player.live': 'Live', 'player.prev': 'Vorige zender', 'player.next': 'Volgende zender', 'player.sleep': 'Slaaptimer', 'player.info': 'Zenderinfo', 'player.share': 'Delen', 'player.open': 'Speler openen', 'player.volume': 'Volume', 'player.loading': 'Verbinden…', 'player.playing': 'Nu live', 'player.paused': 'Gepauzeerd',
      'player.err': 'Deze zender is nu niet bereikbaar', 'player.blocked': 'Deze zender kan alleen in de app worden afgespeeld', 'player.blocked.p': 'De zender gebruikt een onbeveiligde verbinding die browsers blokkeren. In de apps speelt hij wel.', 'player.apps': 'Apps: binnenkort in de App Store en Google Play',
      'sleep.off': 'Uit', 'sleep.min': '{n} min', 'sleep.left': 'Stopt over {t}', 'sleep.set': 'Slaaptimer: {n} minuten', 'sleep.cleared': 'Slaaptimer uit', 'sleep.done': 'Slaaptimer: radio gestopt',
      'search.ph': 'Zenders, genres, steden…', 'search.world': 'Wereldwijd', 'search.genres': 'Populaire genres', 'search.recent': 'Recent gezocht', 'search.clear': 'Wissen', 'search.none': 'Niets gevonden voor "{q}"', 'search.results': 'Resultaten',
      'lib.fav': 'Favorieten', 'lib.recent': 'Recent', 'lib.empty': 'Tik op het hartje bij een zender om hem hier te bewaren', 'lib.empty.r': 'Zenders die je hebt beluisterd, verschijnen hier', 'lib.clear': 'Wissen', 'lib.remove': 'Verwijder uit favorieten',
      'set.country': 'Land', 'set.lang': 'Taal', 'set.system': 'Systeem', 'set.intro': 'Intromuziek', 'set.intro.sub': 'De tune bij het opstarten', 'set.data': 'Gegevens', 'set.clearR': 'Recent wissen', 'set.clearF': 'Favorieten wissen', 'set.confirmR': 'Alle recente zenders wissen?', 'set.confirmF': 'Alle favorieten wissen?', 'set.about': 'Over', 'set.version': 'Versie', 'set.site': 'Website', 'set.privacy': 'Privacy', 'set.terms': 'Voorwaarden', 'set.source': 'Broncode', 'set.credit': 'Zendergegevens: Radio Browser (community)', 'set.credit.p': 'Alle zenders komen uit de open community-database Radio Browser. Ontbreekt er een? Voeg hem daar toe.', 'set.done': 'Gewist', 'set.privacyH': 'Privacy', 'set.stats': 'Anonieme gebruiksstatistieken', 'set.stats.p': 'Geen persoonsgegevens. Alleen het type browser, de versie, het land en de taal die je in Tunr koos en een willekeurig installatienummer worden verstuurd, hooguit twee keer per dag, zodat we zien hoeveel mensen Tunr gebruiken.',
      'toast.fav': 'Bewaard in je favorieten', 'toast.unfav': 'Verwijderd uit je favorieten', 'toast.copied': 'Link gekopieerd', 'toast.region': '{r} is nu je regio',
      'err.load': 'Laden is niet gelukt', 'err.load.p': 'Controleer je verbinding en probeer het opnieuw.', 'empty': 'Hier staan nog geen zenders.',
      'share.text': 'Luister naar {n} op Tunr',
      'nav.label': 'Hoofdmenu', 'home': 'Naar de website',
      'browse.pod': 'Podcasts', 'browse.pod.sub': 'Toplijsten, favorieten en verder luisteren',
      'pod.title': 'Podcasts', 'pod.top': 'Top 50 in {c}', 'pod.genres': 'Genres', 'pod.search': 'Zoek podcasts', 'pod.popular': 'Populaire podcasts in {c}', 'pod.new': 'Nieuwe afleveringen', 'pod.continue': 'Verder luisteren',
      'pod.follow': 'Favoriet', 'pod.following': 'In favorieten', 'pod.favs': 'Favoriete podcasts', 'pod.fav.add': 'Podcast aan favorieten toevoegen', 'pod.fav.remove': 'Podcast uit favorieten verwijderen', 'pod.playLatest': 'Speel nieuwste', 'pod.episodes': 'Afleveringen', 'pod.eps': '{n} afleveringen', 'pod.ep1': '1 aflevering', 'pod.sortNew': 'Nieuwste', 'pod.sortOld': 'Oudste',
      'pod.more': 'Meer lezen', 'pod.less': 'Minder', 'pod.played': 'Beluisterd', 'pod.left': 'nog {t}', 'pod.nf': 'Deze podcast is niet gevonden.', 'pod.epnf': 'Deze aflevering is niet gevonden.', 'pod.noeps': 'Geen afleveringen gevonden.',
      'pod.toast.follow': '{n} staat in je favorieten', 'pod.toast.unfollow': '{n} is uit je favorieten verwijderd', 'pod.lib.empty': 'Tik op het hartje bij een podcast om hem hier te bewaren', 'pod.lib.find': 'Ontdek podcasts', 'pod.none': 'Geen podcasts gevonden voor "{q}"',
      'pod.back15': '15 seconden terug', 'pod.fwd30': '30 seconden vooruit', 'pod.speed': 'Snelheid', 'pod.prev': 'Vorige aflevering', 'pod.next': 'Volgende aflevering', 'pod.seek': 'Positie', 'pod.info': 'Aflevering', 'pod.show': 'Podcast',
      'sleep.eoe': 'Einde van aflevering', 'sleep.eoe.set': 'Slaaptimer: einde van aflevering', 'sleep.eoe.done': 'Slaaptimer: aflevering afgelopen',
      'pod.err': 'Deze aflevering kan nu niet worden afgespeeld', 'pod.blocked': 'Deze aflevering kan alleen in de app worden afgespeeld', 'pod.blocked.p': 'De podcast gebruikt een onbeveiligde verbinding die browsers blokkeren. In de apps speelt hij wel.',
      'seg.stations': 'Zenders', 'seg.podcasts': 'Podcasts', 'pod.ph': 'Podcasts, makers, onderwerpen…', 'pod.results': '{n} podcasts', 'pod.genreFail': 'Genres zijn nu niet beschikbaar.',
      'pg.1489': 'Nieuws', 'pg.1303': 'Comedy', 'pg.1545': 'Sport', 'pg.1488': 'True crime', 'pg.1324': 'Maatschappij & cultuur', 'pg.1321': 'Zakelijk', 'pg.1512': 'Gezondheid', 'pg.1487': 'Geschiedenis', 'pg.1533': 'Wetenschap', 'pg.1318': 'Technologie', 'pg.1305': 'Kinderen & gezin', 'pg.1310': 'Muziek'
    },
    en: {
      'tap.title': 'Every radio station in the world', 'tap.sub': 'Tap to tune in', 'tap.btn': 'Start', 'tap.hint': 'With sound · tap to skip',
      'splash.skip': 'Skip',
      'tab.discover': 'Discover', 'tab.browse': 'Browse', 'tab.map': 'Map', 'tab.search': 'Search', 'tab.library': 'Library', 'tab.settings': 'Settings',
      'greet.morning': 'Good morning', 'greet.afternoon': 'Good afternoon', 'greet.evening': 'Good evening', 'greet.night': 'Good night',
      'country.title': 'Choose your country', 'country.sub': 'You can always change this later', 'country.search': 'Search for a country', 'country.suggested': 'Suggested', 'country.all': 'All countries', 'country.none': 'No country found',
      'stations': '{n} stations', 'station1': '1 station',
      'row.continue': 'Continue listening', 'row.local': 'Local', 'row.popular': 'Popular in {c}', 'row.trending': 'Trending', 'row.favorites': 'Your favourites', 'row.genres': 'Genres', 'row.genre': '{g} in {c}',
      'all': 'See all', 'listen': 'Listen', 'info': 'Info', 'play': 'Play', 'pause': 'Pause', 'stop': 'Stop', 'retry': 'Try again', 'back': 'Back', 'close': 'Close', 'more': 'More',
      'local.pick': 'Choose your region', 'local.pick.sub': 'Stations from your own province or state, right here on Discover.', 'local.make': 'Make this my region', 'local.is': 'Your region', 'local.regions': 'Regions in {c}', 'local.none': 'No regions found for this country.', 'local.filter': 'Search for a region',
      'browse.local': 'Local', 'browse.music': 'Music', 'browse.news': 'News & Talk', 'browse.sports': 'Sports', 'browse.lang': 'By language', 'browse.map': 'World map', 'browse.top': 'Top 100 worldwide',
      'browse.local.sub': 'Your province or state', 'browse.music.sub': 'From pop to classical', 'browse.news.sub': 'News, talk and debate', 'browse.sports.sub': 'Live commentary', 'browse.lang.sub': 'Radio in every language', 'browse.map.sub': 'Spin the globe', 'browse.top.sub': 'Most listened',
      'news.news': 'News', 'news.talk': 'Talk',
      'g.pop': 'Pop', 'g.news': 'News', 'g.rock': 'Rock', 'g.dance': 'Dance', 'g.jazz': 'Jazz', 'g.classical': 'Classical', 'g.hits': 'Hits', 'g.talk': 'Talk', 'g.sports': 'Sports', 'g.oldies': 'Oldies', 'g.hiphop': 'Hip-hop', 'g.country': 'Country', 'g.ambient': 'Ambient', 'g.christian': 'Christian',
      'genre.world': 'Few stations in {c}, so showing worldwide.',
      'map.world': 'World', 'map.country': '{c}', 'map.random': 'Random', 'map.loading': 'Loading map…', 'map.fail.t': 'The map can\'t be loaded right now', 'map.fail.p': 'Check your connection or anything blocking external scripts. Browse and Search still work.', 'map.count': '{n} stations on the map', 'map.none': 'No stations with a location in this country. Try World.', 'map.near': 'Nearby',
      'map.count1': '1 station on the map', 'map.s.ph': 'Search a country or place', 'map.s.label': 'Search the map for a country or place', 'map.s.clear': 'Clear search', 'map.s.countries': 'Countries', 'map.s.places': 'Places', 'map.s.recent': 'Recent searches', 'map.s.none': 'Nothing found for “{q}”', 'map.s.busy': 'Searching places…', 'map.s.around': '{n} stations around {p}', 'map.s.around1': '1 station around {p}', 'map.s.empty': 'No stations with a location found around {p}', 'map.s.country': 'Country',
      'detail.website': 'Website', 'detail.share': 'Share', 'detail.fav': 'Favourite', 'detail.similar': 'Similar stations', 'detail.codec': 'Codec', 'detail.bitrate': 'Bitrate', 'detail.lang': 'Language', 'detail.votes': 'Votes', 'detail.clicks': 'Listeners', 'detail.hls': 'HLS', 'yes': 'yes', 'no': 'no', 'kbps': '{n} kbps', 'detail.nf': 'This station could not be found.', 'detail.np': 'Now playing',
      'player.live': 'Live', 'player.prev': 'Previous station', 'player.next': 'Next station', 'player.sleep': 'Sleep timer', 'player.info': 'Station info', 'player.share': 'Share', 'player.open': 'Open player', 'player.volume': 'Volume', 'player.loading': 'Connecting…', 'player.playing': 'Live now', 'player.paused': 'Paused',
      'player.err': 'This station can\'t be reached right now', 'player.blocked': 'This station can only be played in the app', 'player.blocked.p': 'The station uses an unencrypted connection that browsers block. It plays fine in the apps.', 'player.apps': 'Apps: coming soon to the App Store and Google Play',
      'sleep.off': 'Off', 'sleep.min': '{n} min', 'sleep.left': 'Stops in {t}', 'sleep.set': 'Sleep timer: {n} minutes', 'sleep.cleared': 'Sleep timer off', 'sleep.done': 'Sleep timer: radio stopped',
      'search.ph': 'Stations, genres, cities…', 'search.world': 'Worldwide', 'search.genres': 'Popular genres', 'search.recent': 'Recent searches', 'search.clear': 'Clear', 'search.none': 'Nothing found for "{q}"', 'search.results': 'Results',
      'lib.fav': 'Favourites', 'lib.recent': 'Recent', 'lib.empty': 'Tap the heart on a station to keep it here', 'lib.empty.r': 'Stations you\'ve listened to show up here', 'lib.clear': 'Clear', 'lib.remove': 'Remove from favourites',
      'set.country': 'Country', 'set.lang': 'Language', 'set.system': 'System', 'set.intro': 'Intro music', 'set.intro.sub': 'The tune at start-up', 'set.data': 'Data', 'set.clearR': 'Clear recent', 'set.clearF': 'Clear favourites', 'set.confirmR': 'Clear all recent stations?', 'set.confirmF': 'Clear all favourites?', 'set.about': 'About', 'set.version': 'Version', 'set.site': 'Website', 'set.privacy': 'Privacy', 'set.terms': 'Terms', 'set.source': 'Source code', 'set.credit': 'Station data: Radio Browser (community)', 'set.credit.p': 'All stations come from the open community database Radio Browser. Missing one? Add it there.', 'set.done': 'Cleared', 'set.privacyH': 'Privacy', 'set.stats': 'Anonymous usage statistics', 'set.stats.p': 'No personal data. Only the browser type, the version, the country and language you chose in Tunr and a random install number are sent, at most twice a day, so we can see how many people use Tunr.',
      'toast.fav': 'Saved to your favourites', 'toast.unfav': 'Removed from your favourites', 'toast.copied': 'Link copied', 'toast.region': '{r} is now your region',
      'err.load': 'Couldn\'t load this', 'err.load.p': 'Check your connection and try again.', 'empty': 'No stations here yet.',
      'share.text': 'Listen to {n} on Tunr',
      'nav.label': 'Main menu', 'home': 'Go to the website',
      'browse.pod': 'Podcasts', 'browse.pod.sub': 'Top charts, favourites and resume',
      'pod.title': 'Podcasts', 'pod.top': 'Top 50 in {c}', 'pod.genres': 'Genres', 'pod.search': 'Search podcasts', 'pod.popular': 'Popular podcasts in {c}', 'pod.new': 'New episodes', 'pod.continue': 'Continue listening',
      'pod.follow': 'Favourite', 'pod.following': 'In favourites', 'pod.favs': 'Favourite podcasts', 'pod.fav.add': 'Add podcast to favourites', 'pod.fav.remove': 'Remove podcast from favourites', 'pod.playLatest': 'Play latest', 'pod.episodes': 'Episodes', 'pod.eps': '{n} episodes', 'pod.ep1': '1 episode', 'pod.sortNew': 'Newest', 'pod.sortOld': 'Oldest',
      'pod.more': 'Read more', 'pod.less': 'Less', 'pod.played': 'Played', 'pod.left': '{t} left', 'pod.nf': 'This podcast could not be found.', 'pod.epnf': 'This episode could not be found.', 'pod.noeps': 'No episodes found.',
      'pod.toast.follow': '{n} is in your favourites', 'pod.toast.unfollow': '{n} was removed from your favourites', 'pod.lib.empty': 'Tap the heart on a podcast to keep it here', 'pod.lib.find': 'Discover podcasts', 'pod.none': 'No podcasts found for "{q}"',
      'pod.back15': 'Back 15 seconds', 'pod.fwd30': 'Forward 30 seconds', 'pod.speed': 'Speed', 'pod.prev': 'Previous episode', 'pod.next': 'Next episode', 'pod.seek': 'Position', 'pod.info': 'Episode', 'pod.show': 'Podcast',
      'sleep.eoe': 'End of episode', 'sleep.eoe.set': 'Sleep timer: end of episode', 'sleep.eoe.done': 'Sleep timer: episode finished',
      'pod.err': 'This episode can\'t be played right now', 'pod.blocked': 'This episode can only be played in the app', 'pod.blocked.p': 'The podcast uses an unencrypted connection that browsers block. It plays fine in the apps.',
      'seg.stations': 'Stations', 'seg.podcasts': 'Podcasts', 'pod.ph': 'Podcasts, creators, topics…', 'pod.results': '{n} podcasts', 'pod.genreFail': 'Genres aren\'t available right now.',
      'pg.1489': 'News', 'pg.1303': 'Comedy', 'pg.1545': 'Sports', 'pg.1488': 'True crime', 'pg.1324': 'Society & culture', 'pg.1321': 'Business', 'pg.1512': 'Health', 'pg.1487': 'History', 'pg.1533': 'Science', 'pg.1318': 'Technology', 'pg.1305': 'Kids & family', 'pg.1310': 'Music'
    }
  };

  function lang() { return T.store ? T.store.lang : 'nl'; }
  T.t = function (key, vars) {
    var l = lang();
    var s = (S[l] && S[l][key]) || S.nl[key] || key;
    if (vars) s = s.replace(/\{(\w+)\}/g, function (m, k) { return vars[k] != null ? vars[k] : m; });
    return s;
  };
  T.locale = function () { return lang() === 'nl' ? 'nl-NL' : 'en-GB'; };
  T.num = function (n) { return Number(n || 0).toLocaleString(T.locale()); };
  T.stationsN = function (n) { return n === 1 ? T.t('station1') : T.t('stations', { n: T.num(n) }); };

  T.flag = function (cc) {
    cc = String(cc || '').toUpperCase();
    if (!/^[A-Z]{2}$/.test(cc)) return '🌐';
    return String.fromCodePoint(cc.charCodeAt(0) + 127397, cc.charCodeAt(1) + 127397);
  };
  var dnCache = {};
  T.countryName = function (cc, fallback) {
    cc = String(cc || '').toUpperCase();
    var l = lang();
    try {
      if (!dnCache[l]) dnCache[l] = new Intl.DisplayNames([l], { type: 'region' });
      var n = dnCache[l].of(cc);
      if (n && n !== cc) return n;
    } catch (e) {}
    return fallback || cc;
  };
  var lnCache = {};
  T.languageName = function (name, code) {
    var l = lang();
    if (code) {
      try {
        if (!lnCache[l]) lnCache[l] = new Intl.DisplayNames([l], { type: 'language' });
        var n = lnCache[l].of(String(code).split(',')[0].trim());
        if (n && n.toLowerCase() !== String(code).toLowerCase()) return n.charAt(0).toUpperCase() + n.slice(1);
      } catch (e) {}
    }
    name = String(name || '');
    return name.charAt(0).toUpperCase() + name.slice(1);
  };

  T.esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };

  // ---------- StationArt (SPEC §1) ----------
  T.PALETTE = [['#FF5A1F', '#FFB020'], ['#7C3AED', '#DB2777'], ['#0EA5E9', '#22D3EE'], ['#10B981', '#84CC16'],
    ['#F43F5E', '#FB923C'], ['#6366F1', '#06B6D4'], ['#EAB308', '#F97316'], ['#14B8A6', '#3B82F6']];
  T.hash = function (s) { var h = 0; s = String(s || ''); for (var i = 0; i < s.length; i++) { h = (h * 31 + s.charCodeAt(i)) | 0; } return Math.abs(h); };
  T.pal = function (name) { return T.PALETTE[T.hash(String(name || '').toLowerCase()) % T.PALETTE.length]; };
  T.monogram = function (name) {
    var w = String(name || '?').replace(/[^\p{L}\p{N}\s]/gu, ' ').trim().split(/\s+/).filter(Boolean);
    if (!w.length) return '?';
    var m = w.length > 1 && /^\p{L}/u.test(w[1]) ? w[0].charAt(0) + w[1].charAt(0) : Array.from(w[0]).slice(0, 2).join('');
    return m.toUpperCase();
  };
  T.logoUrl = function (u) {
    u = String(u || '').trim();
    if (!/^https?:\/\//i.test(u)) return '';
    if (location.protocol === 'https:') u = u.replace(/^http:/i, 'https:'); // gemengde inhoud vermijden
    return u;
  };
  // ---------- App Store-iconen (SPEC §1) ----------
  // Vaste tabel per land, gemaakt door tools/make_station_icons.py (workflow Icons): assets/data/icons/<CC>.json
  // (zenders zonder land: _world.json) = {"u": {stationuuid: url}, "n": {naamsleutel: url}}. Pas geladen als een
  // zender uit dat land getoond wordt; bewaard in localStorage (7 dagen). Komt een tabel binnen nadat een
  // zendercover al getekend is, dan wordt die cover opnieuw gemaakt (zie iconUpgrade).
  var ICON_BASE = (function () {
    try { var cs = document.currentScript; return new URL('../data/icons/', (cs && cs.src) || location.href).href; }
    catch (e) { return '/assets/data/icons/'; }
  })();
  var ICON_TTL = 6 * 36e5, IK = 'tunr.icons2:', iconTabs = {}, iconWait = {}, iconRetry = {}, artReg = {};
  // naamsleutel, gelijk aan norm_key in tools/make_station_icons.py (en Apple/Android): NFKD, accenten weg,
  // kleine letters, alleen letters en decimale cijfers
  T.iconKey = function (name) {
    return String(name || '').normalize('NFKD').replace(/\p{Mn}/gu, '').toLowerCase().replace(/[^\p{L}\p{Nd}]/gu, '');
  };
  function iconFile(s) { var cc = String((s && s.cc) || '').toUpperCase(); return /^[A-Z]{2}$/.test(cc) ? cc : '_world'; }
  function iconReady(f) { return !!iconTabs[f] || (iconRetry[f] || 0) > Date.now(); }
  function iconLoad(f) {
    if (iconReady(f)) return Promise.resolve();
    if (iconWait[f]) return iconWait[f];
    var stale = null;
    try {
      var raw = localStorage.getItem(IK + f);
      if (raw) {
        var o = JSON.parse(raw);
        if (o && o.v && o.e > Date.now()) { iconTabs[f] = o.v; return Promise.resolve(); }
        if (o && o.v) stale = o.v;
      }
    } catch (e) {}
    iconWait[f] = fetch(ICON_BASE + f + '.json').then(function (r) {
      if (r.status === 404) return {}; // nog geen iconen voor dit land (1 dag onthouden)
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.json();
    }).then(function (t) {
      t = t && typeof t === 'object' ? t : {};
      iconTabs[f] = t;
      var empty = !t.u && !t.n;
      try { localStorage.setItem(IK + f, JSON.stringify({ e: Date.now() + (empty ? 864e5 : ICON_TTL), v: t })); } catch (e) {}
    }, function () {
      if (stale) iconTabs[f] = stale; else iconRetry[f] = Date.now() + 10 * 6e4;
    }).then(function () { delete iconWait[f]; iconUpgrade(f); });
    return iconWait[f];
  }
  // App Store-icoon van de zender als de tabel van het land er al is ('' = niet (of nog niet) bekend)
  T.iconFor = function (s) {
    var t = s && iconTabs[iconFile(s)];
    if (!t) return '';
    var u = (t.u && t.u[s.id]) || (t.n && t.n[T.iconKey(s.name)]) || '';
    return /^https:\/\//i.test(u) ? u : '';
  };
  // wacht (max. 1,5 s) op de tabellen van een zenderlijst, zodat de eerste weergave al de App Store-iconen heeft;
  // bij veel landen (kaart wereldwijd) niet wachten: dan laadt elke cover zijn land zelf
  T.iconsReady = function (arr) {
    var files = [];
    (arr || []).forEach(function (s) { var f = iconFile(s); if (files.indexOf(f) < 0) files.push(f); });
    if (!files.length || files.length > 3) return Promise.resolve(arr);
    var all = Promise.all(files.map(iconLoad));
    return Promise.race([all, new Promise(function (r) { setTimeout(r, 1500); })]).then(function () { return arr; }, function () { return arr; });
  };
  // tabel binnen: covers van zenders uit dat land met een App Store-icoon opnieuw maken
  function iconUpgrade(f) {
    var els = document.querySelectorAll('.art[data-st]');
    for (var i = 0; i < els.length; i++) {
      var el = els[i], s = artReg[el.getAttribute('data-st')];
      if (!s || iconFile(s) !== f) continue;
      var ic = T.iconFor(s);
      if (!ic || logoBad[ic] || logoGood[s.id] === ic) continue;
      var im = el.querySelector('img.logo');
      if (im && im.getAttribute('data-cur') === ic) continue;
      delete logoGood[s.id];
      var tmp = document.createElement('span');
      tmp.innerHTML = T.art(s, el.getAttribute('data-cls') || '');
      if (tmp.firstChild) el.replaceWith(tmp.firstChild);
    }
  }

  // ---------- zenderlogo's met terugval ----------
  // 1. App Store-icoon uit de tabel; 2. Google-favicondienst op het domein van de homepage (sz=256); 3. favicon uit
  // Radio Browser (http → https); 4. DuckDuckGo-favicondienst; 5. monogram. De eerste bron van minstens 96 px
  // (grootste zijde) wint; kleinere logo's alleen als laatste redmiddel (het grootste), Google onder 96 px en
  // DuckDuckGo onder 48 px nooit. Mislukte URL's en het gekozen logo per zender onthouden we deze sessie.
  var LOGO_GOOD = 96, LOGO_MIN = 48, LOGO_MIN_GOOGLE = 96, logoBad = {}, logoTiny = {}, logoGood = {}, logoLook = {};
  function isLogoService(u) { return /^https:\/\/(www\.google\.com\/s2\/favicons|icons\.duckduckgo\.com\/ip3\/)/i.test(u); }
  // mag een klein logo (grootste zijde px) als terugval? Google nooit onder 96, DuckDuckGo niet onder 48
  function logoSmallOk(u, px) {
    if (!(px >= 8)) return false;
    if (/^https:\/\/www\.google\.com\/s2\/favicons/i.test(u)) return px >= LOGO_MIN_GOOGLE;
    if (/^https:\/\/icons\.duckduckgo\.com\/ip3\//i.test(u)) return px >= LOGO_MIN;
    return true;
  }
  // grootste bekende kleine logo uit een lijst
  function bestTiny(list) {
    var best = '', bp = 0;
    list.forEach(function (u) { if (logoTiny[u] > bp && !logoBad[u]) { best = u; bp = logoTiny[u]; } });
    return best;
  }

  // ---------- weergave van een logo (SPEC §1) ----------
  // Groot logo (kleinste zijde ≥ 0,75 × tegel in pixels of ≥ 160 px) vult de tegel (object-fit: cover); klein logo
  // gecentreerd (contain), hooguit 2× zijn eigen pixelmaat en hooguit 62% van de tegel. Altijd op een effen
  // achtergrond uit het logo zelf: dekkende randpixels → hun gemiddelde kleur; transparant → wit bij een donker/
  // gekleurd logo, #16161A bij een licht/wit logo. Pixels lezen kan alleen met CORS: een verborgen probe-afbeelding
  // met crossOrigin; lukt dat niet (of gooit getImageData), dan wit. Per URL onthouden.
  var LOGO_SURFACE = '#16161a', LOGO_WHITE = '#ffffff';
  function hex2(n) { n = Math.max(0, Math.min(255, Math.round(n))); return (n < 16 ? '0' : '') + n.toString(16); }
  function lookFromPixels(d) {
    var n = 24, edgeT = 0, edgeO = 0, er = 0, eg = 0, eb = 0, solid = 0, light = 0;
    for (var y = 0; y < n; y++) for (var x = 0; x < n; x++) {
      var i = (y * n + x) * 4, a = d[i + 3] / 255, r = d[i] / 255, g = d[i + 1] / 255, b = d[i + 2] / 255;
      if (x === 0 || y === 0 || x === n - 1 || y === n - 1) {
        edgeT++;
        if (a >= 0.9) { edgeO++; er += r; eg += g; eb += b; }
      }
      if (a >= 0.5) {
        solid++;
        var lum = 0.2126 * r + 0.7152 * g + 0.0722 * b, sat = Math.max(r, g, b) - Math.min(r, g, b);
        if (lum > 0.78 && sat < 0.2) light++;
      }
    }
    if (edgeT && edgeO >= 0.75 * edgeT) return '#' + hex2(er / edgeO * 255) + hex2(eg / edgeO * 255) + hex2(eb / edgeO * 255);
    return solid && light > 0.6 * solid ? LOGO_SURFACE : LOGO_WHITE;
  }
  var lookWait = {};
  function probeLook(url) {
    if (logoLook[url] || lookWait[url]) return;
    lookWait[url] = 1;
    var done = function (bg) {
      delete lookWait[url];
      logoLook[url] = bg;
      // al getekende covers met dit logo bijwerken
      var imgs = document.querySelectorAll('.art img.logo[data-lk]');
      for (var i = 0; i < imgs.length; i++) {
        if (imgs[i].getAttribute('data-cur') === url && imgs[i].parentNode) imgs[i].parentNode.style.background = bg;
      }
    };
    var im = new Image();
    im.crossOrigin = 'anonymous';
    im.referrerPolicy = 'no-referrer';
    im.decoding = 'async';
    im.onload = function () {
      var bg = LOGO_WHITE;
      try {
        var c = document.createElement('canvas'); c.width = 24; c.height = 24;
        var cx = c.getContext('2d');
        cx.imageSmoothingEnabled = true;
        cx.drawImage(im, 0, 0, 24, 24);
        bg = lookFromPixels(cx.getImageData(0, 0, 24, 24).data);
      } catch (e) { bg = LOGO_WHITE; }
      done(bg);
    };
    im.onerror = function () { done(LOGO_WHITE); };
    im.src = url;
  }
  // maat en achtergrond toepassen op een goedgekeurd logo
  function applyLook(el, url) {
    var lt = el.parentNode, a = el.closest('.art');
    if (!lt) return;
    var w = el.naturalWidth || 0, h = el.naturalHeight || 0, dpr = window.devicePixelRatio || 1;
    var tilePx = (a ? a.clientWidth : 0) * dpr, mn = Math.min(w, h), mx = Math.max(w, h);
    var large = mn >= 160 || (tilePx > 0 && mn >= 0.75 * tilePx);
    lt.classList.toggle('sm', !large);
    if (large) { el.style.width = ''; el.style.height = ''; }
    else { var box = 'min(62%, ' + Math.max(1, Math.round(2 * mx / dpr)) + 'px)'; el.style.width = box; el.style.height = box; }
    lt.style.background = logoLook[url] || LOGO_WHITE;
    if (!logoLook[url]) probeLook(url);
  }
  // domein van de homepage ("https://www.npo.nl/radio2" → "www.npo.nl"), of ''
  T.logoHost = function (hp) {
    hp = String(hp || '').trim();
    if (!hp) return '';
    if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(hp)) hp = 'http://' + hp;
    try {
      var h = new URL(hp).hostname.toLowerCase();
      return /^[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(h) ? h : '';
    } catch (e) { return ''; }
  };
  // alle bronnen in volgorde (zonder de URL's die deze sessie al mislukten)
  T.logoCandidates = function (s) {
    var out = [], ic = T.iconFor(s), f = T.logoUrl(s && s.favicon), h = T.logoHost(s && s.homepage);
    if (ic) out.push(ic);
    if (h) out.push('https://www.google.com/s2/favicons?domain=' + encodeURIComponent(h) + '&sz=256');
    if (f) out.push(f);
    if (h) out.push('https://icons.duckduckgo.com/ip3/' + h + '.ico');
    return out.filter(function (u, i) { return !logoBad[u] && out.indexOf(u) === i; });
  };
  // beste bekende logo voor achtergronden en de mediasessie (een eerder geladen bron, anders de eerste kandidaat)
  T.logoBest = function (s) {
    if (s && logoGood[s.id]) return logoGood[s.id];
    var c = T.logoCandidates(s).filter(function (u) { return !logoTiny[u]; });
    return c[0] || '';
  };
  // cls: extra klassen (bijv. 'lg'); de equalizer staat altijd in de art en is alleen zichtbaar bij .is-playing
  T.art = function (s, cls) {
    // tabel van het land nog niet geladen: nu laden (de cover wordt daarna zo nodig opnieuw gemaakt)
    var ifile = iconFile(s);
    if (!iconReady(ifile) && s && s.id) iconLoad(ifile);
    if (s && s.id) artReg[s.id] = s;
    var p = T.pal(s.name), all = T.logoCandidates(s);
    var good = logoGood[s.id] && !logoBad[logoGood[s.id]] ? logoGood[s.id] : '';
    // kleine logo's pas als laatste redmiddel (het grootste)
    var tiny = bestTiny(all);
    var list = good ? [good] : all.filter(function (u) { return !logoTiny[u]; });
    var first = list[0] || tiny;
    return '<span class="art ' + (cls || '') + '" style="--a:' + p[0] + ';--b:' + p[1] + '" aria-hidden="true"' +
      (s.id ? ' data-st="' + T.esc(s.id) + '" data-cls="' + T.esc(cls || '') + '"' : '') + '>' +
      '<span class="mono">' + T.esc(T.monogram(s.name)) + '</span>' +
      (first ? '<span class="lt"><img class="logo" src="' + T.esc(first) + '" data-lk="' + T.esc(s.id || '') + '" data-cur="' + T.esc(first) +
        '" data-alt="' + T.esc(list.slice(1).join(' ')) + '"' + (tiny && tiny !== first ? ' data-tiny="' + T.esc(tiny) + '"' : '') +
        (first === tiny ? ' data-final="1"' : '') + ' alt="" loading="lazy" decoding="async" referrerpolicy="no-referrer"></span>' : '') +
      '<span class="eq"><i></i><i></i><i></i><i></i></span></span>';
  };
  function dropLogo(el) { var lt = el.parentNode; if (lt && lt.parentNode) lt.parentNode.classList.remove('has-logo'); if (lt) lt.remove(); }
  function acceptLogo(el) {
    var a = el.closest('.art');
    if (el.hasAttribute('data-lk')) applyLook(el, el.getAttribute('data-cur') || el.src);
    if (a) a.classList.add('has-logo');
  }
  // volgende bron proberen; op = monogram (of het kleine favicon als laatste redmiddel)
  function nextLogo(el) {
    var alts = (el.getAttribute('data-alt') || '').split(' ').filter(function (u) { return u && !logoBad[u]; });
    var nxt = alts.shift();
    if (nxt) { el.setAttribute('data-alt', alts.join(' ')); el.setAttribute('data-cur', nxt); el.src = nxt; return; }
    var tiny = el.getAttribute('data-tiny');
    if (tiny && !logoBad[tiny]) { el.removeAttribute('data-tiny'); el.setAttribute('data-final', '1'); el.setAttribute('data-cur', tiny); el.src = tiny; return; }
    dropLogo(el);
  }
  // mislukte logo's → volgende bron of monogram; geladen logo's → monogram weg. (load/error bubbelen niet: capture)
  document.addEventListener('error', function (e) {
    var el = e.target;
    if (!el || el.tagName !== 'IMG' || !el.classList.contains('logo')) return;
    if (el.hasAttribute('data-lk')) { logoBad[el.getAttribute('data-cur')] = 1; nextLogo(el); return; }
    dropLogo(el);
  }, true);
  document.addEventListener('load', function (e) {
    var el = e.target;
    if (!el || el.tagName !== 'IMG' || !el.classList.contains('logo')) return;
    if (!el.hasAttribute('data-lk')) {
      if (el.naturalWidth < 8) { var lt = el.parentNode; lt && lt.remove(); return; }
      acceptLogo(el);
      return;
    }
    var cur = el.getAttribute('data-cur') || '', lk = el.getAttribute('data-lk'), w = el.naturalWidth;
    var px = Math.max(el.naturalWidth || 0, el.naturalHeight || 0);
    // al gekozen voor deze zender, of het laatste redmiddel: gebruiken
    if ((lk && logoGood[lk] === cur && px >= 8) || el.hasAttribute('data-final')) {
      if (w >= 8) { if (lk) logoGood[lk] = cur; acceptLogo(el); } else { logoBad[cur] = 1; if (lk && logoGood[lk] === cur) delete logoGood[lk]; dropLogo(el); }
      return;
    }
    if (px >= LOGO_GOOD) { if (lk) logoGood[lk] = cur; acceptLogo(el); return; }
    if (!logoSmallOk(cur, px)) { logoBad[cur] = 1; nextLogo(el); return; }
    // klein logo: bewaren als laatste redmiddel (het grootste); zijn er geen andere bronnen meer, dan het grootste
    logoTiny[cur] = px;
    var rest = (el.getAttribute('data-alt') || '').split(' ').filter(function (u) { return u && !logoBad[u]; });
    var prev = el.getAttribute('data-tiny') || '', best = bestTiny(prev ? [prev, cur] : [cur]);
    if (!rest.length) {
      if (best === cur) { el.setAttribute('data-final', '1'); el.removeAttribute('data-tiny'); if (lk) logoGood[lk] = cur; acceptLogo(el); return; }
      el.setAttribute('data-tiny', best);
      nextLogo(el);
      return;
    }
    el.setAttribute('data-tiny', best);
    nextLogo(el);
  }, true);

  T.place = function (s) {
    var parts = [];
    if (s.state && s.state.toLowerCase() !== String(s.country).toLowerCase()) parts.push(s.state);
    if (s.cc) parts.push(T.countryName(s.cc, s.country) + ' ' + T.flag(s.cc)); else if (s.country) parts.push(s.country);
    return parts.join(' · ');
  };
  T.genreLabel = function (tag) { var k = 'g.' + tag; var v = T.t(k); return v === k ? tag.charAt(0).toUpperCase() + tag.slice(1) : v; };
  // tijd: 1:05:09 / 4:07
  T.clock = function (sec) {
    sec = Math.max(0, Math.floor(sec || 0));
    var h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60), x = sec % 60;
    return (h ? h + ':' + (m < 10 ? '0' : '') : '') + m + ':' + (x < 10 ? '0' : '') + x;
  };
  // duur: "1 u 5 min" / "42 min"
  T.dur = function (sec) {
    sec = Math.round(sec || 0); if (!sec) return '';
    var h = Math.floor(sec / 3600), m = Math.round(sec % 3600 / 60);
    if (m === 60) { h++; m = 0; }
    var u = lang() === 'nl' ? 'u' : 'h';
    return h ? h + ' ' + u + (m ? ' ' + m + ' min' : '') : Math.max(1, m) + ' min';
  };
  T.date = function (iso) {
    if (!iso) return '';
    var d = new Date(iso); if (isNaN(d)) return '';
    var o = { day: 'numeric', month: 'short' };
    if (d.getFullYear() !== new Date().getFullYear()) o.year = 'numeric';
    try { return d.toLocaleDateString(T.locale(), o); } catch (e) { return d.toDateString(); }
  };
  T.epsN = function (n) { return n === 1 ? T.t('pod.ep1') : T.t('pod.eps', { n: T.num(n) }); };
  T.podGenre = function (id) { var k = 'pg.' + id; var v = T.t(k); return v === k ? '' : v; };
  // PodcastArt: de hoes van iTunes, met een verloop + monogram eronder als terugval
  T.podArt = function (p, cls) {
    var pl = T.pal(p.name || p.pname || p.title), u = T.logoUrl(p.art);
    return '<span class="art pod ' + (cls || '') + '" style="--a:' + pl[0] + ';--b:' + pl[1] + '" aria-hidden="true">' +
      '<span class="mono">' + T.esc(T.monogram(p.name || p.pname || p.title)) + '</span>' +
      (u ? '<span class="lt"><img class="logo" src="' + T.esc(u) + '" alt="" loading="lazy" decoding="async" referrerpolicy="no-referrer"></span>' : '') +
      '<span class="eq"><i></i><i></i><i></i><i></i></span></span>';
  };
  T.tagsLine = function (s, n) { return (s.tags || []).slice(0, n || 3).map(function (t) { return T.genreLabel(t); }).join(', '); };
})();
