// "Add to Home Screen" guide for iPhone/iPad. Apple doesn't let a website install itself,
// so this shows exactly where to tap, with an arrow pointing at the right button.
// Shown when TalkMe is opened in the browser (not from the home screen), at most every 3 days,
// or right away with ?install=1 (the iPhone button on talkme.space links there).
(function () {
  // The https address of TalkMe (Cloudflare Worker in front of talkme.space). On plain http the
  // iPhone can't use the camera, microphone or notifications, so the guide sends people there first.
  var SECURE_URL = 'https://talkme.ghostzero270.workers.dev/app/?install=1';
  var insecure = location.protocol === 'http:' && location.hostname !== 'localhost';

  var ua = navigator.userAgent;
  var ios = /iPhone|iPad|iPod/.test(ua) || (ua.indexOf('Macintosh') > -1 && navigator.maxTouchPoints > 1);
  if (!ios) return;
  var installed = window.navigator.standalone === true ||
    (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches);
  if (installed) return;

  var forced = /[?&]install=1/.test(location.search);
  var key = 'talkme_install_guide';
  try {
    var last = parseInt(localStorage.getItem(key) || '0', 10);
    if (!forced && Date.now() - last < 3 * 24 * 3600 * 1000) return;
  } catch (e) {}

  var ipad = /iPad/.test(ua) || ua.indexOf('Macintosh') > -1;
  var inApp = /FBAN|FBAV|Instagram|Line\/|TikTok|Snapchat|Messenger/.test(ua); // in-app browsers can't install
  var chrome = /CriOS|EdgiOS|FxiOS/.test(ua);  // other browsers on iPhone: Share is in the address bar
  var m = ua.match(/Version\/(\d+)/);
  var safari26 = !chrome && m && parseInt(m[1], 10) >= 26; // Safari 26: Share sits in the ••• menu

  var lang = 'en';
  try {
    var saved = JSON.parse(localStorage.getItem('flutter.lang') || 'null');
    lang = saved || ((navigator.language || '').toLowerCase().indexOf('sq') === 0 ? 'sq' : 'en');
  } catch (e) {}
  var T = {
    en: {
      title: 'Install TalkMe',
      sub: 'Add it to your Home Screen. It opens full screen, like a normal app, and can send you notifications.',
      share: 'Tap the Share button',
      shareMore: 'Tap the ••• button, then Share',
      shareBar: 'Tap the Share button in the address bar',
      add: 'Scroll down and choose “Add to Home Screen”',
      done: 'Tap “Add”. TalkMe appears on your Home Screen.',
      inApp: 'This app’s browser can’t install TalkMe. Tap ••• and choose “Open in Safari”, then come back to this page.',
      later: 'Not now',
      here: 'Tap here',
      secureTitle: 'Open the secure TalkMe',
      secureSub: 'Install TalkMe from its secure address. There the camera, microphone and notifications work too. Sign in again once it opens.',
      secureBtn: 'Open secure TalkMe'
    },
    sq: {
      title: 'Instalo TalkMe',
      sub: 'Shtoje në ekranin kryesor. Hapet në ekran të plotë si një aplikacion i zakonshëm dhe mund të të dërgojë njoftime.',
      share: 'Shtyp butonin Ndaj (Share)',
      shareMore: 'Shtyp butonin •••, pastaj Ndaj (Share)',
      shareBar: 'Shtyp butonin Ndaj (Share) te shiriti i adresës',
      add: 'Rrëshqit poshtë dhe zgjidh “Shto në ekranin kryesor” (Add to Home Screen)',
      done: 'Shtyp “Shto” (Add). TalkMe shfaqet në ekranin kryesor.',
      inApp: 'Shfletuesi i këtij aplikacioni nuk mund ta instalojë TalkMe. Shtyp ••• dhe zgjidh “Hap në Safari”, pastaj kthehu në këtë faqe.',
      later: 'Jo tani',
      here: 'Shtyp këtu',
      secureTitle: 'Hap TalkMe të sigurt',
      secureSub: 'Instalo TalkMe nga adresa e tij e sigurt. Atje funksionojnë edhe kamera, mikrofoni dhe njoftimet. Hyr përsëri sapo të hapet.',
      secureBtn: 'Hap TalkMe të sigurt'
    }
  }[lang === 'sq' ? 'sq' : 'en'];

  var shareSvg = '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12"/><path d="M8 7l4-4 4 4"/><path d="M6 11H5a1 1 0 0 0-1 1v8a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-8a1 1 0 0 0-1-1h-1"/></svg>';
  var addSvg = '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="4"/><path d="M12 8v8M8 12h8"/></svg>';
  var okSvg = '<svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12l5 5L20 7"/></svg>';
  var dotsSvg = '<svg viewBox="0 0 24 24" width="22" height="22" fill="currentColor"><circle cx="5" cy="12" r="2"/><circle cx="12" cy="12" r="2"/><circle cx="19" cy="12" r="2"/></svg>';

  // Where Safari puts the button: bottom middle on iPhone, ••• bottom right on Safari 26, top right on iPad and other browsers.
  var spot = inApp ? 'top-right' : (ipad || chrome) ? 'top-right' : safari26 ? 'bottom-right' : 'bottom';

  var css = '' +
    '#ig{position:fixed;inset:0;z-index:2147483647;background:rgba(5,8,7,.86);-webkit-backdrop-filter:blur(6px);backdrop-filter:blur(6px);' +
    'font:15px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#fff;display:flex;align-items:center;justify-content:center;padding:20px;' +
    'animation:igIn .25s ease-out}' +
    '@keyframes igIn{from{opacity:0}to{opacity:1}}' +
    '#ig .card{width:100%;max-width:380px;background:#121816;border:1px solid rgba(255,255,255,.08);border-radius:24px;padding:22px 20px 16px;box-shadow:0 20px 60px rgba(0,0,0,.5)}' +
    '#ig .head{display:flex;gap:14px;align-items:center;margin-bottom:10px}' +
    '#ig .head img{width:56px;height:56px;border-radius:14px}' +
    '#ig h2{margin:0;font-size:21px}' +
    '#ig .sub{color:#a9b5b1;font-size:14px;margin:0 0 14px}' +
    '#ig ol{list-style:none;margin:0;padding:0}' +
    '#ig li{display:flex;gap:12px;align-items:center;padding:9px 0}' +
    '#ig li .ic{flex:none;width:40px;height:40px;border-radius:12px;background:rgba(20,163,127,.18);color:#3ddc9f;display:flex;align-items:center;justify-content:center}' +
    '#ig li b{font-weight:600}' +
    '#ig .go,#ig .later{box-sizing:border-box}#ig .go{display:block;width:100%;margin-top:12px;padding:14px;border:0;border-radius:14px;background:linear-gradient(135deg,#1fc394,#0e7a5d);color:#fff;font:700 16px -apple-system,sans-serif;text-align:center;text-decoration:none}' +
    '#ig .later{display:block;width:100%;margin-top:10px;padding:13px;border:0;border-radius:14px;background:rgba(255,255,255,.08);color:#fff;font:600 15px -apple-system,sans-serif}' +
    '#ig .arrow{position:fixed;display:flex;flex-direction:column;align-items:center;gap:4px;color:#3ddc9f;font-weight:700;font-size:13px;pointer-events:none}' +
    '#ig .arrow svg{filter:drop-shadow(0 2px 8px rgba(61,220,159,.6))}' +
    '#ig .arrow.bottom{left:50%;bottom:calc(6px + env(safe-area-inset-bottom));transform:translateX(-50%);animation:igDown 1s ease-in-out infinite}' +
    '#ig .arrow.bottom-right{right:14px;bottom:calc(6px + env(safe-area-inset-bottom));animation:igDown 1s ease-in-out infinite}' +
    '#ig .arrow.top-right{right:14px;top:calc(4px + env(safe-area-inset-top));animation:igUp 1s ease-in-out infinite}' +
    '@keyframes igDown{0%,100%{translate:0 0}50%{translate:0 10px}}' +
    '@keyframes igUp{0%,100%{translate:0 0}50%{translate:0 -10px}}';

  var arrowDown = '<svg viewBox="0 0 24 24" width="44" height="44" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v17"/><path d="M5 13l7 7 7-7"/></svg>';
  var arrowUp = '<svg viewBox="0 0 24 24" width="44" height="44" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 21V4"/><path d="M5 11l7-7 7 7"/></svg>';

  var steps = inApp
    ? '<li><span class="ic">' + dotsSvg + '</span><span>' + T.inApp + '</span></li>'
    : '<li><span class="ic">' + (safari26 ? dotsSvg : shareSvg) + '</span><span><b>' +
        (safari26 ? T.shareMore : chrome || ipad ? T.shareBar : T.share) + '</b></span></li>' +
      '<li><span class="ic">' + addSvg + '</span><span>' + T.add + '</span></li>' +
      '<li><span class="ic">' + okSvg + '</span><span>' + T.done + '</span></li>';

  function show() {
    if (document.getElementById('ig')) return;
    var style = document.createElement('style');
    style.textContent = css;
    document.head.appendChild(style);
    var el = document.createElement('div');
    el.id = 'ig';
    el.setAttribute('role', 'dialog');
    if (insecure) {
      el.innerHTML =
        '<div class="card">' +
          '<div class="head"><img src="icons/apple-touch-icon.png" alt=""><div><h2>' + T.secureTitle + '</h2></div></div>' +
          '<p class="sub">' + T.secureSub + '</p>' +
          '<a class="go" href="' + SECURE_URL + '">' + T.secureBtn + '</a>' +
          '<button class="later" type="button">' + T.later + '</button>' +
        '</div>';
      el.querySelector('.later').addEventListener('click', close);
      document.body.appendChild(el);
      return;
    }
    el.innerHTML =
      '<div class="card">' +
        '<div class="head"><img src="icons/apple-touch-icon.png" alt=""><div><h2>' + T.title + '</h2></div></div>' +
        '<p class="sub">' + T.sub + '</p>' +
        '<ol>' + steps + '</ol>' +
        '<button class="later" type="button">' + T.later + '</button>' +
      '</div>' +
      '<div class="arrow ' + spot + '">' + (spot === 'top-right' ? arrowUp : '') + '<span>' + T.here + '</span>' +
        (spot === 'top-right' ? '' : arrowDown) + '</div>';
    el.querySelector('.later').addEventListener('click', close);
    document.body.appendChild(el);
  }

  function close() {
    try { localStorage.setItem(key, String(Date.now())); } catch (e) {}
    var el = document.getElementById('ig');
    if (el) el.remove();
  }

  // Safari hides its toolbar while the page scrolls; the guide is shown right away so it is visible.
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', show); else show();
})();
