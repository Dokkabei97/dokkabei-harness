// Hook stdin helper — reads JSON event payload and provides passthrough.

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
