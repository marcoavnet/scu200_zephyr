/******************************************************************************
 * Copyright (c) 2026 Marco Höfle, Avnet-Silica
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files to deal in the software
 * without restriction, including without limitation the rights to use, copy,
 * modify, merge, publish, distribute, sublicense, and/or sell copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
 ******************************************************************************/

/* SPDX-License-Identifier: MIT */
(function () {
  'use strict';
  const $ = id => document.getElementById(id);
  const colors = ['#42cfff', '#ffab49', '#64e7a0', '#c899ff'];
  const tabs = [...document.querySelectorAll('[role="tab"]')];
  let active = 'live', frozen = false, latest = null, shown = null, device = null;
  let socket = null, reconnectTimer, backoff = 500, wsOpen = false;
  let lastActivity = 0, lastFrame = 0, dirty = true, spectrumCache = null;
  let controlBusy = false, statusBusy = false, statusAvailable = false;
  let received = 0, invalidFrames = 0;
  const events = [];
  const number = x => Number(x).toLocaleString('en-US');

  function event(message) {
    events.push(`${new Date().toLocaleTimeString()}  ${message}`);
    if (events.length > 80) events.shift();
    $('events').textContent = events.join('\n');
    $('events').scrollTop = $('events').scrollHeight;
  }
  function card(label, value, className = 'status-card') {
    const el = document.createElement('div'); el.className = className;
    const l = document.createElement('span'); l.textContent = label;
    const v = document.createElement('strong'); v.textContent = value;
    el.append(l, v); return el;
  }
  const timeCanvases = [], fftCanvases = [];
  for (let c = 0; c < 4; c++) {
    for (const [parent, array, label] of [['live-plots', timeCanvases, 'time-domain samples'], ['fft-plots', fftCanvases, 'spectrum in dBFS']]) {
      const div = document.createElement('div'); div.className = 'plot';
      const canvas = document.createElement('canvas');
      canvas.setAttribute('role', 'img'); canvas.setAttribute('aria-label', `CH${c} ${label}`);
      div.append(canvas); $(parent).append(div); array.push(canvas);
    }
    const el = document.createElement('div'); el.className = 'sample-card'; el.style.setProperty('--channel', colors[c]);
    const label = document.createElement('span'); label.textContent = `CH${c} · last sample`;
    const value = document.createElement('strong'); value.id = `last-${c}`; value.textContent = '—';
    const range = document.createElement('small'); range.id = `range-${c}`; range.textContent = 'Waiting for data';
    el.append(label, value, range); $('sample-cards').append(el);
  }

  function selectTab(id) {
    active = id;
    tabs.forEach(tab => {
      const selected = tab.getAttribute('aria-controls') === id;
      tab.setAttribute('aria-selected', String(selected)); tab.tabIndex = selected ? 0 : -1;
      $(tab.getAttribute('aria-controls')).hidden = !selected;
    });
    dirty = true;
  }
  tabs.forEach((tab, i) => {
    tab.addEventListener('click', () => selectTab(tab.getAttribute('aria-controls')));
    tab.addEventListener('keydown', e => {
      let next;
      if (e.key === 'ArrowRight') next = (i + 1) % tabs.length;
      if (e.key === 'ArrowLeft') next = (i + tabs.length - 1) % tabs.length;
      if (e.key === 'Home') next = 0;
      if (e.key === 'End') next = tabs.length - 1;
      if (next !== undefined) { e.preventDefault(); tabs[next].focus(); tabs[next].click(); }
    });
  });

  document.querySelectorAll('.freeze').forEach(button => button.addEventListener('click', () => {
    frozen = !frozen;
    document.querySelectorAll('.freeze').forEach(b => { b.textContent = frozen ? 'Resume' : 'Freeze'; b.setAttribute('aria-pressed', String(frozen)); });
    if (!frozen) shown = latest;
    dirty = true; updateConnection();
  }));
  $('fft-window').addEventListener('change', () => { spectrumCache = null; dirty = true; });

  function draw(canvas, data, c, fft) {
    const rect = canvas.getBoundingClientRect();
    if (!rect.width || !rect.height) return;
    const ratio = Math.min(window.devicePixelRatio || 1, 2);
    const w = rect.width, h = rect.height;
    if (canvas.width !== Math.round(w * ratio) || canvas.height !== Math.round(h * ratio)) {
      canvas.width = Math.round(w * ratio); canvas.height = Math.round(h * ratio);
    }
    const ctx = canvas.getContext('2d'); ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    ctx.fillStyle = '#101a2b'; ctx.fillRect(0, 0, w, h);
    const left = 54, right = w - 12, top = 22, bottom = h - 23;
    const min = fft ? -120 : -32768, max = fft ? 0 : 32767;
    const yticks = fft ? [0, -30, -60, -90, -120] : [32767, 16384, 0, -16384, -32768];
    const py = v => bottom - (Math.min(max, Math.max(min, v)) - min) / (max - min) * (bottom - top);
    ctx.font = '10px monospace'; ctx.lineWidth = .7;
    for (const y of yticks) {
      const pixel = py(y); ctx.strokeStyle = y === 0 ? '#4b5e75' : '#2b3b50';
      ctx.beginPath(); ctx.moveTo(left, pixel); ctx.lineTo(right, pixel); ctx.stroke();
      ctx.fillStyle = '#b4c3d9'; ctx.fillText(String(y), 3, pixel + 3);
    }
    for (let i = 0; i <= 4; i++) {
      const x = left + i / 4 * (right - left);
      ctx.strokeStyle = '#2b3b50'; ctx.beginPath(); ctx.moveTo(x, top); ctx.lineTo(x, bottom); ctx.stroke();
      const text = data ? String(Math.round(i / 4 * (data.length - 1))) : '—';
      ctx.fillStyle = '#b4c3d9'; ctx.textAlign = i === 4 ? 'right' : i === 0 ? 'left' : 'center';
      ctx.fillText(text, x, h - 6);
    }
    ctx.textAlign = 'left'; ctx.fillStyle = colors[c]; ctx.fillText(`CH${c} (${fft ? 'dBFS' : 'int16'})`, left, 13);
    if (data) {
      ctx.save(); ctx.beginPath(); ctx.rect(left, top, right - left, bottom - top); ctx.clip();
      ctx.strokeStyle = colors[c]; ctx.lineWidth = .9; ctx.beginPath();
      for (let i = 0; i < data.length; i++) {
        const x = left + i / (data.length - 1) * (right - left), y = py(data[i]);
        if (!i) ctx.moveTo(x, y); else ctx.lineTo(x, y);
      }
      ctx.stroke(); ctx.restore();
    } else {
      ctx.fillStyle = '#8093ad'; ctx.fillText('Waiting for live samples…', left + 10, (top + bottom) / 2);
    }
  }

  function render() {
    if (dirty && (active === 'live' || active === 'fft')) {
      dirty = false;
      if (!shown) {
        const canvases = active === 'live' ? timeCanvases : fftCanvases;
        canvases.forEach((canvas, c) => draw(canvas, null, c, active === 'fft'));
      } else {
        const f = shown;
        if (active === 'live') {
          $('live-meta').textContent = `Chunk ${number(f.sequence)} · ${number(f.count)} samples/channel · ${f.channels} channels · int16 LE · sample index 0–${f.count - 1}${frozen ? ' · FROZEN' : ''}`;
          f.samples.forEach((samples, c) => {
            draw(timeCanvases[c], samples, c, false);
            let min = 32767, max = -32768;
            for (const v of samples) { if (v < min) min = v; if (v > max) max = v; }
            $(`last-${c}`).textContent = String(samples[samples.length - 1]);
            $(`range-${c}`).textContent = `min ${min} / max ${max}`;
          });
        } else {
          const windowName = $('fft-window').value;
          if (!spectrumCache || spectrumCache.frame !== f || spectrumCache.windowName !== windowName) {
            spectrumCache = {frame:f, windowName, data:f.samples.map(s => LiveDSP.fftSpectrum(s, windowName))};
          }
          const resolution = f.sampleRate ? ` · Fs ${number(f.sampleRate)} Hz · Δf ${(f.sampleRate / f.count).toFixed(3)} Hz/bin` : ' · sample rate unknown';
          $('fft-meta').textContent = `Chunk ${number(f.sequence)} · ${f.count}-point FFT · bins 0–${Math.floor(f.count / 2)}${resolution}${frozen ? ' · FROZEN' : ''}`;
          spectrumCache.data.forEach((s, c) => draw(fftCanvases[c], s, c, true));
        }
      }
    }
    requestAnimationFrame(render);
  }
  new ResizeObserver(() => { dirty = true; }).observe(document.querySelector('main'));
  window.addEventListener('resize', () => { dirty = true; });
  requestAnimationFrame(render);

  function badge(el, text, kind) { el.textContent = text; el.className = `badge ${kind}`; }
  function updateConnection() {
    const now = performance.now();
    if (!wsOpen) badge($('connection'), 'Server disconnected — reconnecting', 'warning');
    else if (now - lastActivity > 15000) badge($('connection'), 'Connection unresponsive', 'error');
    else if (frozen) badge($('connection'), 'Connected · display frozen', 'neutral');
    else if (device && !device.stream_enabled) badge($('connection'), 'Connected · stream paused', 'neutral');
    else if (!latest) badge($('connection'), 'Connected · waiting for samples', 'warning');
    else if (now - lastFrame > 2000) badge($('connection'), 'Connected · sample data stale', 'warning');
    else badge($('connection'), 'Connected · live', 'good');
    if (latest) badge($('source-badge'), latest.demo ? 'DEMO DATA' : 'SENSOR DATA', latest.demo ? 'warning' : 'good');
    else if (device) badge($('source-badge'), device.source === 'demo' ? 'DEMO DATA' : 'Waiting for source', 'warning');
  }

  function connect() {
    clearTimeout(reconnectTimer);
    const url = `${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/ws/live`;
    socket = new WebSocket(url); socket.binaryType = 'arraybuffer';
    socket.onopen = () => {
      wsOpen = true; backoff = 500; lastActivity = performance.now();
      event('WebSocket connected'); updateConnection();
    };
    socket.onmessage = e => {
      lastActivity = performance.now();
      if (typeof e.data === 'string') return; // application heartbeat pong
      try {
        const frame = LiveDSP.decodeFrame(e.data);
        latest = frame; received++; lastFrame = performance.now();
        if (!frozen) { shown = frame; dirty = true; }
        updateConnection();
      } catch (err) {
        invalidFrames++;
        if (invalidFrames <= 3) event(`Rejected live frame: ${err.message}`);
      }
    };
    socket.onerror = () => {}; // onclose handles retry and event reporting
    socket.onclose = () => {
      wsOpen = false; updateConnection(); event('WebSocket disconnected; retrying');
      reconnectTimer = setTimeout(connect, backoff); backoff = Math.min(backoff * 2, 5000);
    };
  }
  connect();
  setInterval(() => {
    if (wsOpen && socket.readyState === WebSocket.OPEN) {
      if (performance.now() - lastActivity > 15000) socket.close();
      else socket.send('ping');
    }
    updateConnection();
  }, 5000);

  async function fetchJSON(path, options = {}) {
    const controller = new AbortController(), timer = setTimeout(() => controller.abort(), 4000);
    try {
      const response = await fetch(path, {...options, cache:'no-store', signal:controller.signal});
      const body = await response.json();
      if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`);
      return body;
    } finally { clearTimeout(timer); }
  }
  function uptime(ms) {
    const sec = Math.floor(ms / 1000);
    return `${Math.floor(sec / 3600)}h ${Math.floor(sec / 60) % 60}m ${sec % 60}s`;
  }
  function refreshControls() {
    const available = statusAvailable && !controlBusy;
    $('led-on').disabled = !available || !device?.led1_ready;
    $('led-off').disabled = !available || !device?.led1_ready;
    $('stream-toggle').disabled = !available;
    if (device) {
      $('led-state').textContent = !device.led1_ready ? 'GPIO unavailable' : device.led1 ? 'On' : 'Off';
      $('stream-state').textContent = device.stream_enabled ? 'Transmission enabled' : 'Transmission paused';
      $('stream-toggle').textContent = device.stream_enabled ? 'Pause stream' : 'Resume stream';
    }
  }
  function renderStatus(s) {
    $('device-title').textContent = s.device; document.title = s.device;
    const data = [
      ['Stream', s.stream_enabled ? 'Enabled' : 'Paused'], ['Uptime', uptime(s.uptime_ms)],
      ['Source', s.source === 'demo' ? 'Demo waveforms' : s.source === 'sensor' ? 'Sensors' : 'Waiting'],
      ['Published chunk', number(s.sequence)], ['Sent frames', number(s.sent)],
      ['Acquisition drops', number(s.dropped)], ['Sample age', s.has_frame ? `${number(s.frame_age_ms)} ms` : '—'],
      ['Browser frames', number(received)], ['Send failures', number(s.send_errors)]
    ];
    $('status-cards').replaceChildren(...data.map(([k, v]) => card(k, v)));
    const info = [ ['Device', s.device], ['Board target', s.board], ['Zephyr', s.zephyr], ['Firmware built', s.built],
      ['Channels', String(s.channels)], ['Maximum samples/channel', number(s.max_frames)],
      ['Current samples/channel', s.has_frame ? number(s.frames) : '—'],
      ['Sample rate', s.sample_rate_hz ? `${number(s.sample_rate_hz)} Hz` : 'Unknown'],
      ['Maximum UI update rate', `${s.update_rate_hz} Hz`], ['Sample format', 'Interleaved signed int16, little endian'],
      ['Live clients', `${s.ws_clients} / 1`], ['FFT', 'Exact N-point, one-sided, window gain compensated'] ];
    const entries = [];
    info.forEach(([key, value]) => { const dt = document.createElement('dt'), dd = document.createElement('dd'); dt.textContent = key; dd.textContent = value; entries.push(dt, dd); });
    $('device-info').replaceChildren(...entries);
  }
  async function pollStatus() {
    if (statusBusy) return;
    statusBusy = true;
    try {
      device = await fetchJSON('/api/status');
      if (!statusAvailable) event(`Device status available · Zephyr ${device.zephyr}`);
      statusAvailable = true; renderStatus(device);
    } catch (err) {
      if (statusAvailable) event(`Status request failed: ${err.message}`);
      statusAvailable = false;
    } finally { statusBusy = false; refreshControls(); updateConnection(); }
  }
  async function command(endpoint, enabled, message) {
    if (controlBusy) return;
    controlBusy = true; refreshControls();
    $('control-result').textContent = 'Applying…'; $('control-result').className = '';
    try {
      await fetchJSON(endpoint, {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify({enabled})});
      $('control-result').textContent = message; event(message);
      if (device) { if (endpoint === '/api/led') device.led1 = enabled; else device.stream_enabled = enabled; }
      await pollStatus();
    } catch (err) {
      $('control-result').textContent = `Command failed: ${err.message}`; $('control-result').className = 'failed';
      event(`Control error: ${err.message}`);
    } finally { controlBusy = false; refreshControls(); updateConnection(); }
  }
  $('led-on').addEventListener('click', () => command('/api/led', true, 'LED1 switched on'));
  $('led-off').addEventListener('click', () => command('/api/led', false, 'LED1 switched off'));
  $('stream-toggle').addEventListener('click', () => { if (device) command('/api/stream', !device.stream_enabled, device.stream_enabled ? 'Stream paused' : 'Stream resumed'); });
  (async function pollLoop() { await pollStatus(); setTimeout(pollLoop, 1000); })();
})();
