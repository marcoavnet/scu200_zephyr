/* SPDX-License-Identifier: MIT */
/* Pure browser/Node DSP and wire decoding. No external packages. */
(function (root) {
  'use strict';
  function decodeFrame(buffer) {
    if (!(buffer instanceof ArrayBuffer) || buffer.byteLength < 32) throw new Error('Short live frame');
    const d = new DataView(buffer);
    if (d.getUint32(0, true) !== 0x31564c5a || d.getUint16(4, true) !== 32) throw new Error('Unknown live protocol');
    const channels = d.getUint16(6, true), count = d.getUint32(8, true);
    if (channels !== 4 || count < 2 || count > 4096 || buffer.byteLength !== 32 + channels * count * 2) throw new Error('Invalid live frame size');
    const samples = Array.from({length:channels}, () => new Int16Array(count));
    for (let i = 0; i < count; i++) for (let c = 0; c < channels; c++) samples[c][i] = d.getInt16(32 + (i * channels + c) * 2, true);
    return {samples, count, channels, sampleRate:d.getUint32(12, true), sequence:d.getUint32(16, true),
      demo:!!(d.getUint32(20, true) & 1), timestamp:d.getUint32(24, true) + d.getUint32(28, true) * 4294967296};
  }
  function radix2(re, im, inverse) {
    const n = re.length;
    for (let i = 1, j = 0; i < n; i++) {
      let bit = n >> 1;
      for (; j & bit; bit >>= 1) j ^= bit;
      j ^= bit;
      if (i < j) { [re[i], re[j]] = [re[j], re[i]]; [im[i], im[j]] = [im[j], im[i]]; }
    }
    for (let len = 2; len <= n; len *= 2) {
      const a = (inverse ? 2 : -2) * Math.PI / len, wr0 = Math.cos(a), wi0 = Math.sin(a);
      for (let i = 0; i < n; i += len) {
        let wr = 1, wi = 0;
        for (let j = 0; j < len / 2; j++) {
          const u = i + j, v = u + len / 2;
          const tr = re[v] * wr - im[v] * wi, ti = re[v] * wi + im[v] * wr;
          re[v] = re[u] - tr; im[v] = im[u] - ti; re[u] += tr; im[u] += ti;
          const next = wr * wr0 - wi * wi0; wi = wr * wi0 + wi * wr0; wr = next;
        }
      }
    }
    if (inverse) for (let i = 0; i < n; i++) { re[i] /= n; im[i] /= n; }
  }
  let plan;
  function getPlan(n) {
    if (plan && plan.n === n) return plan;
    let m = 1; while (m < 2 * n - 1) m *= 2;
    const cos = new Float64Array(n), sin = new Float64Array(n);
    const br = new Float64Array(m), bi = new Float64Array(m), hann = new Float64Array(n);
    let gain = 0;
    for (let i = 0; i < n; i++) {
      const angle = Math.PI * ((i * i) % (2 * n)) / n;
      cos[i] = Math.cos(angle); sin[i] = Math.sin(angle);
      br[i] = cos[i]; bi[i] = sin[i];
      if (i) { br[m - i] = cos[i]; bi[m - i] = sin[i]; }
      hann[i] = .5 - .5 * Math.cos(2 * Math.PI * i / (n - 1)); gain += hann[i];
    }
    radix2(br, bi, false);
    plan = {n, m, cos, sin, br, bi, hann, gain, ar:new Float64Array(m), ai:new Float64Array(m)};
    return plan;
  }
  function fftSpectrum(samples, windowName = 'hann') {
    const n = samples.length;
    if (n < 2 || n > 4096) throw new Error('Unsupported FFT length');
    const p = getPlan(n), {ar, ai} = p;
    ar.fill(0); ai.fill(0);
    const useHann = windowName === 'hann' && n > 2;
    const gain = useHann ? p.gain : n;
    // Bluestein computes an EXACT N-point FFT, including N=2000. The internal
    // convolution padding does not change the displayed bin spacing Fs/N.
    for (let i = 0; i < n; i++) {
      const x = samples[i] * (useHann ? p.hann[i] : 1);
      ar[i] = x * p.cos[i]; ai[i] = -x * p.sin[i];
    }
    radix2(ar, ai, false);
    for (let i = 0; i < p.m; i++) {
      const r = ar[i] * p.br[i] - ai[i] * p.bi[i];
      ai[i] = ar[i] * p.bi[i] + ai[i] * p.br[i]; ar[i] = r;
    }
    radix2(ar, ai, true);
    const out = new Float32Array(Math.floor(n / 2) + 1);
    for (let k = 0; k < out.length; k++) {
      const factor = k === 0 || (n % 2 === 0 && k === n / 2) ? 1 : 2;
      const amplitude = factor * Math.hypot(ar[k], ai[k]) / (gain * 32768);
      out[k] = Math.max(-120, 20 * Math.log10(Math.max(amplitude, 1e-12)));
    }
    return out;
  }
  root.LiveDSP = {decodeFrame, fftSpectrum};
  if (typeof module !== 'undefined' && module.exports) module.exports = root.LiveDSP;
})(globalThis);
