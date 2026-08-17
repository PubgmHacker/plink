// Smoke-test the v97 ip-stripping logic against realistic googlevideo URLs.
// Run: node /home/z/my-project/scripts/test-ip-strip.js

function stripIpParam(decoded) {
  let cleaned = decoded.replace(/&amp;/g, '&');
  cleaned = cleaned.replace(/[&?]ip=[^&]+/g, '');
  if (!cleaned.includes('?')) {
    const firstAmp = cleaned.indexOf('&');
    if (firstAmp !== -1) {
      cleaned = cleaned.substring(0, firstAmp) + '?' + cleaned.substring(firstAmp + 1);
    }
  }
  cleaned = cleaned.replace(/&&/g, '&').replace(/[?&]$/, '');
  return cleaned;
}

const cases = [
  {
    name: 'ip in middle',
    url: 'https://r1---sn-xxx.googlevideo.com/videoplayback?expire=1234567890&ip=1.2.3.4&mime=video%2Fmp4&clen=12345',
    expectContains: ['expire=1234567890', 'mime=video%2Fmp4', 'clen=12345'],
    expectNotContains: ['ip=1.2.3.4'],
  },
  {
    name: 'ip is first param',
    url: 'https://r1---sn-xxx.googlevideo.com/videoplayback?ip=10.0.0.1&mime=video%2Fmp4&expire=9999',
    expectContains: ['mime=video%2Fmp4', 'expire=9999'],
    expectNotContains: ['ip=10.0.0.1'],
  },
  {
    name: 'ip is last param',
    url: 'https://r1---sn-xxx.googlevideo.com/videoplayback?mime=video%2Fmp4&expire=9999&ip=5.6.7.8',
    expectContains: ['mime=video%2Fmp4', 'expire=9999'],
    expectNotContains: ['ip=5.6.7.8'],
  },
  {
    name: 'ip is only param',
    url: 'https://r1---sn-xxx.googlevideo.com/videoplayback?ip=192.168.1.1',
    expectContains: ['/videoplayback'],
    expectNotContains: ['ip=192.168.1.1', '?', '&'],
  },
  {
    name: 'html entities + ip in middle',
    url: 'https://r1---sn-xxx.googlevideo.com/videoplayback?expire=1&amp;ip=1.2.3.4&amp;mime=video',
    expectContains: ['expire=1', 'mime=video'],
    expectNotContains: ['ip=1.2.3.4', '&amp;'],
  },
  {
    name: 'ipv6 in ip param',
    url: 'https://r1---sn-xxx.googlevideo.com/videoplayback?expire=1&ip=2001:db8::1&mime=video',
    expectContains: ['expire=1', 'mime=video'],
    expectNotContains: ['ip=2001:db8::1'],
  },
];

let pass = 0, fail = 0;
for (const c of cases) {
  const out = stripIpParam(c.url);
  let ok = true;
  const reasons = [];
  for (const s of c.expectContains) {
    if (!out.includes(s)) { ok = false; reasons.push(`missing: "${s}"`); }
  }
  for (const s of c.expectNotContains) {
    if (out.includes(s)) { ok = false; reasons.push(`should not contain: "${s}"`); }
  }
  if (!out.startsWith('https://')) { ok = false; reasons.push('not https://'); }
  const qCount = (out.match(/\?/g) || []).length;
  if (qCount > 1) { ok = false; reasons.push(`multiple ? (${qCount})`); }
  if (/[?&]$/.test(out)) { ok = false; reasons.push('dangling separator'); }
  if (/&&/.test(out)) { ok = false; reasons.push('double &'); }
  console.log(`${ok ? 'PASS' : 'FAIL'} ${c.name}`);
  console.log(`   in : ${c.url}`);
  console.log(`   out: ${out}`);
  if (!ok) {
    console.log(`   REASONS: ${reasons.join('; ')}`);
    fail++;
  } else {
    pass++;
  }
}
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
