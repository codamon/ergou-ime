// 二狗输入法 landing page. Two small things, no network, no storage:
// 1. the hero typing demo, 2. today's date in the "rq" example.
(function () {
  'use strict';

  var today = document.getElementById('today');
  if (today) {
    var d = new Date();
    today.textContent = d.getFullYear() + '年' + (d.getMonth() + 1) + '月' + d.getDate() + '日';
  }

  var compose = document.getElementById('compose');
  var committed = document.getElementById('committed');
  var cand = document.getElementById('cand');
  if (!compose || !committed || !cand) return;
  if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  var items = cand.querySelectorAll('li b');
  var full = 'jintiantianqizhenbucuo';
  // Candidates shown once the typed pinyin reaches a given length.
  var stages = [
    [1, ['就', '见', '将', '家', '及']],
    [3, ['今', '金', '进', '近', '仅']],
    [7, ['今天', '金田', '今', '金', '进']],
    [13, ['今天天气', '今天', '今', '金', '进']],
    [22, ['今天天气真不错', '今天天气', '今天', '今', '金']]
  ];

  function show(n) {
    compose.textContent = full.slice(0, n);
    var list = stages[0][1];
    for (var i = 0; i < stages.length; i++) if (n >= stages[i][0]) list = stages[i][1];
    for (var j = 0; j < items.length; j++) items[j].textContent = list[j];
    cand.hidden = n === 0;
  }

  var n = 0, timer;
  function step() {
    if (n < full.length) {
      n++;
      show(n);
      timer = setTimeout(step, 70 + Math.random() * 90);
    } else {
      timer = setTimeout(commit, 1500);
    }
  }
  function commit() {
    committed.textContent = '今天天气真不错';
    compose.textContent = '';
    cand.hidden = true;
    timer = setTimeout(reset, 2600);
  }
  function reset() {
    committed.textContent = '';
    n = 0;
    show(0);
    timer = setTimeout(step, 700);
  }

  // Only run while the demo is on screen.
  var running = false;
  function start() { if (!running) { running = true; reset(); } }
  function stop() { running = false; clearTimeout(timer); }
  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (entries) {
      entries[0].isIntersecting ? start() : stop();
    }, { threshold: 0.2 }).observe(cand.parentNode);
  } else {
    start();
  }
})();
