// Hook stdin helper — reads JSON event payload and provides passthrough.
// base/bin/hooks/_lib/hook-stdin.js 의 자체 포함 복사본 (플러그인 간 require 경로 의존 제거).

exports.readEvent = () => new Promise((resolve) => {
  let buf = '';
  process.stdin.on('data', (c) => { buf += c; });
  process.stdin.on('end', () => {
    let json = {};
    try { json = JSON.parse(buf); } catch (_) {}
    resolve({ raw: buf, json });
  });
});

exports.passthrough = (raw) => { console.log(raw); };
