// ============================================================================
// BLE & Wi-Fi Configuration
// ============================================================================
const BLE_SERVICE_UUID     = '19b10000-e8f2-537e-4f6c-d104768a1214';
const BLE_CHAR_STATE_UUID  = '19b10001-e8f2-537e-4f6c-d104768a1214';
const BLE_CHAR_TAP_UUID    = '19b10003-e8f2-537e-4f6c-d104768a1214';

// App State
let bleDevice = null;
let gattServer = null;
let charState = null;
let charTap = null;

let currentWavBlob = null;
let currentWavUrl = null;
let currentActiveClipId = null;
let audioContext = null;
let currentAudioBuffer = null;
let currentSourceNode = null;
let isPlaying = false;
let playbackStartTime = 0;
let playbackOffset = 0;
let animationFrameId = null;

// Decoded Audio Data
let rawMonoPcm = null;
let sampleRate = 16000;
let synchronizedClips = [];

// DOM Elements
const btnConnect = document.getElementById('btnConnect');
const btnConnectText = document.getElementById('btnConnectText');
const connectionBadge = document.getElementById('connectionBadge');
const stateRing = document.getElementById('stateRing');
const stateLabel = document.getElementById('stateLabel');
const stateDesc = document.getElementById('stateDesc');
const tapPulse = document.getElementById('tapPulse');
const tapText = document.getElementById('tapText');
const wifiIpInput = document.getElementById('wifiIpInput');
const btnSyncWifi = document.getElementById('btnSyncWifi');
const btnSyncText = document.getElementById('btnSyncText');
const currentClipTitle = document.getElementById('currentClipTitle');
const waveformCanvas = document.getElementById('waveformCanvas');
const emptyWaveformMessage = document.getElementById('emptyWaveformMessage');
const volumeBoostSlider = document.getElementById('volumeBoostSlider');
const boostValEl = document.getElementById('boostVal');
const noiseGateSlider = document.getElementById('noiseGateSlider');
const gateValEl = document.getElementById('gateVal');
const btnPlay = document.getElementById('btnPlay');
const btnPlayText = document.getElementById('btnPlayText');
const playIcon = document.getElementById('playIcon');
const btnDownload = document.getElementById('btnDownload');
const seekSlider = document.getElementById('seekSlider');
const currentTimeEl = document.getElementById('currentTime');
const totalTimeEl = document.getElementById('totalTime');
const clipMetaEl = document.getElementById('clipMeta');
const clipsList = document.getElementById('clipsList');

// ============================================================================
// Mono IMA-ADPCM Decoder (4-Bit 8 KB/s)
// ============================================================================
const ADPCM_STEP_TABLE = [
  7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
  50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 
  253, 279, 307, 337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 
  1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066, 2272, 2499, 2749, 3024, 3327, 
  3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 
  12635, 13899, 15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767
];
const ADPCM_INDEX_TABLE = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8];

function decodeMonoImaAdpcm(arrayBuffer) {
  const dataView = new DataView(arrayBuffer);
  let dataOffset = 60;
  let dataLength = arrayBuffer.byteLength - 60;

  // Scan chunks to locate 'data' offset
  let offset = 12;
  while (offset < arrayBuffer.byteLength - 8) {
    const chunkId = String.fromCharCode(
      dataView.getUint8(offset), dataView.getUint8(offset+1),
      dataView.getUint8(offset+2), dataView.getUint8(offset+3)
    );
    const chunkSize = dataView.getUint32(offset + 4, true);
    if (chunkId === 'data') {
      dataOffset = offset + 8;
      dataLength = chunkSize;
      break;
    }
    offset += 8 + chunkSize;
  }

  const rawBytes = new Uint8Array(arrayBuffer, dataOffset, dataLength);
  const numSamples = rawBytes.length * 2;
  const pcm = new Int16Array(numSamples);

  let pred = 0, stepIdx = 0;

  function decodeNibble(nibble) {
    let step = ADPCM_STEP_TABLE[stepIdx];
    let diffq = step >> 3;
    if (nibble & 4) diffq += step;
    if (nibble & 2) diffq += (step >> 1);
    if (nibble & 1) diffq += (step >> 2);

    if (nibble & 8) pred -= diffq;
    else pred += diffq;

    if (pred > 32767) pred = 32767;
    else if (pred < -32768) pred = -32768;

    let nextIdx = stepIdx + ADPCM_INDEX_TABLE[nibble & 0x0F];
    if (nextIdx < 0) nextIdx = 0;
    else if (nextIdx > 88) nextIdx = 88;
    stepIdx = nextIdx;

    return pred;
  }

  let sampleIdx = 0;
  for (let i = 0; i < rawBytes.length; i++) {
    const byte = rawBytes[i];
    pcm[sampleIdx++] = decodeNibble(byte & 0x0F);
    pcm[sampleIdx++] = decodeNibble((byte >> 4) & 0x0F);
  }

  return { pcm, numSamples };
}

// ============================================================================
// Audio Processing & Playback Engine
// ============================================================================
function applyAudioEffects() {
  if (!rawMonoPcm || !audioContext) return;

  const boostFactor = volumeBoostSlider ? (parseInt(volumeBoostSlider.value) / 100.0) : 1.5;
  if (boostValEl) boostValEl.textContent = `${Math.round(boostFactor * 100)}%`;

  const gatePercent = parseInt(noiseGateSlider.value) / 100.0;
  const gateThreshold = gatePercent * 800; // Threshold in 16-bit units
  if (gateValEl) gateValEl.textContent = `${Math.round(gatePercent * 100)}%`;

  const numSamples = rawMonoPcm.length;
  currentAudioBuffer = audioContext.createBuffer(1, numSamples, sampleRate);
  const ch0 = currentAudioBuffer.getChannelData(0);
  const processedInt16 = new Int16Array(numSamples);

  for (let i = 0; i < numSamples; i++) {
    let val = rawMonoPcm[i] * boostFactor;

    // Noise Gate
    if (Math.abs(val) < gateThreshold) {
      val = 0;
    }

    processedInt16[i] = Math.max(-32768, Math.min(32767, val));
    ch0[i] = processedInt16[i] / 32768.0;
  }

  drawWaveform(processedInt16);

  const duration = currentAudioBuffer.duration;
  totalTimeEl.textContent = formatTime(duration);
  seekSlider.max = duration;
}

function onAudioSettingsChanged() {
  const wasPlaying = isPlaying;
  const currentOffset = playbackOffset;

  if (isPlaying) pausePlayback();
  applyAudioEffects();

  if (wasPlaying) startPlayback(currentOffset);
}

// ============================================================================
// Standard Linear 16-Bit PCM WAV Exporter (Format Tag 0x0001)
// Fully compatible with Windows Media Player, VLC, QuickTime, Android, Audacity
// ============================================================================
function audioBufferToPcmWavBlob(buffer) {
  const numChannels = buffer.numberOfChannels;
  const sampleRate = buffer.sampleRate;
  const numFrames = buffer.length;
  const bytesPerSample = 2;
  const blockAlign = numChannels * bytesPerSample;
  const byteRate = sampleRate * blockAlign;
  const dataSize = numFrames * blockAlign;
  const headerSize = 44;
  const totalSize = headerSize + dataSize;

  const arrayBuffer = new ArrayBuffer(totalSize);
  const view = new DataView(arrayBuffer);

  // RIFF header
  view.setUint8(0, 0x52); // 'R'
  view.setUint8(1, 0x49); // 'I'
  view.setUint8(2, 0x46); // 'F'
  view.setUint8(3, 0x46); // 'F'
  view.setUint32(4, 36 + dataSize, true);
  view.setUint8(8, 0x57); // 'W'
  view.setUint8(9, 0x41); // 'A'
  view.setUint8(10, 0x56); // 'V'
  view.setUint8(11, 0x45); // 'E'

  // fmt subchunk (PCM)
  view.setUint8(12, 0x66); // 'f'
  view.setUint8(13, 0x6d); // 'm'
  view.setUint8(14, 0x74); // 't'
  view.setUint8(15, 0x20); // ' '
  view.setUint32(16, 16, true);       // Subchunk1Size = 16 for PCM
  view.setUint16(20, 1, true);        // AudioFormat = 1 (Linear PCM)
  view.setUint16(22, numChannels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, 16, true);       // BitsPerSample = 16

  // data subchunk
  view.setUint8(36, 0x64); // 'd'
  view.setUint8(37, 0x61); // 'a'
  view.setUint8(38, 0x74); // 't'
  view.setUint8(39, 0x61); // 'a'
  view.setUint32(40, dataSize, true);

  // Write 16-bit PCM samples
  let offset = 44;
  for (let i = 0; i < numFrames; i++) {
    for (let channel = 0; channel < numChannels; channel++) {
      let sample = buffer.getChannelData(channel)[i];
      sample = Math.max(-1.0, Math.min(1.0, sample));
      let int16 = sample < 0 ? (sample * 32768) : (sample * 32767);
      view.setInt16(offset, int16, true);
      offset += 2;
    }
  }

  return new Blob([view], { type: 'audio/wav' });
}

// ============================================================================
// BLE Live Signaling
// ============================================================================
async function toggleBleConnection() {
  if (bleDevice && bleDevice.gatt && bleDevice.gatt.connected) {
    disconnectBle();
  } else {
    connectBle();
  }
}

async function connectBle() {
  if (!navigator.bluetooth) {
    alert('Web Bluetooth wird nicht unterstützt. Du kannst alle Daten jederzeit direkt über WLAN synchronisieren!');
    return;
  }

  try {
    btnConnectText.textContent = 'Suche...';
    
    bleDevice = await navigator.bluetooth.requestDevice({
      filters: [{ name: 'XIAO-Audio-Recorder' }],
      optionalServices: [BLE_SERVICE_UUID]
    });

    bleDevice.addEventListener('gattserverdisconnected', onDisconnected);

    btnConnectText.textContent = 'Verbinde...';
    gattServer = await bleDevice.gatt.connect();
    await new Promise(r => setTimeout(r, 500));

    const service = await gattServer.getPrimaryService(BLE_SERVICE_UUID);

    charState = await service.getCharacteristic(BLE_CHAR_STATE_UUID);
    await charState.startNotifications();
    charState.addEventListener('characteristicvaluechanged', onStateChanged);

    charTap = await service.getCharacteristic(BLE_CHAR_TAP_UUID);
    await charTap.startNotifications();
    charTap.addEventListener('characteristicvaluechanged', onTapEvent);

    btnConnect.classList.add('connected');
    btnConnectText.textContent = 'BLE Verbunden';
    connectionBadge.textContent = 'BLE Online';
    connectionBadge.className = 'badge badge-connected';
    
    updateDeviceState(0);
    console.log('[BLE] Connected & Subscribed!');

  } catch (err) {
    console.warn('[BLE Warning]', err);
    btnConnectText.textContent = 'BLE Live-Signal';
  }
}

function disconnectBle() {
  if (bleDevice && bleDevice.gatt && bleDevice.gatt.connected) {
    bleDevice.gatt.disconnect();
  }
  onDisconnected();
}

function onDisconnected() {
  btnConnect.classList.remove('connected');
  btnConnectText.textContent = 'BLE Live-Signal';
  connectionBadge.textContent = 'BLE Standby';
  connectionBadge.className = 'badge badge-disconnected';
  console.log('[BLE] Disconnected.');
}

function onStateChanged(event) {
  const data = event.target.value;
  if (data.byteLength < 1) return;

  const state = data.getUint8(0);
  const latestClipId = data.byteLength >= 5 ? data.getUint32(1, true) : 0;
  const totalClips = data.byteLength >= 7 ? data.getUint16(5, true) : 0;

  updateDeviceState(state, latestClipId, totalClips);
}

function updateDeviceState(state, latestClipId = 0, totalClips = 0) {
  stateRing.className = 'state-ring';

  switch (state) {
    case 0: // IDLE
      stateRing.classList.add('state-idle');
      stateLabel.textContent = 'Bereit';
      stateDesc.textContent = 'Hau auf das Breadboard, um eine Aufnahme zu starten (LED leuchtet).';
      break;

    case 1: // RECORDING
      stateRing.classList.add('state-recording');
      stateLabel.textContent = 'Aufnahme läuft (Dual-Mic Noise Filter 8 KB/s)...';
      stateDesc.textContent = 'Sprich ins Mikrofon! Hau nochmals auf das Breadboard zum Beenden & Speichern.';
      break;

    case 3: // DONE / SAVED_TO_FLASH
      stateRing.classList.add('state-idle');
      stateLabel.textContent = `Aufnahme #${latestClipId} im Flash gespeichert!`;
      stateDesc.textContent = `Gesamt ${totalClips} Aufnahme(n) im Flash bereit zur WLAN-Synchronisation.`;
      break;
  }
}

function onTapEvent(event) {
  const data = event.target.value;
  if (data.byteLength >= 5) {
    const shockRaw = data.getInt32(1, true);
    const shockG = (shockRaw / 1000.0).toFixed(2);
    
    tapPulse.classList.add('active');
    tapText.textContent = `Tap! (${shockG}g)`;
    
    setTimeout(() => {
      tapPulse.classList.remove('active');
      tapText.textContent = 'Ruhe';
    }, 400);
  }
}

// ============================================================================
// Multi-Clip Wi-Fi Synchronization Engine
// ============================================================================
async function syncAllClipsFromWifi() {
  const ip = wifiIpInput.value.trim() || '192.168.4.1';
  btnSyncWifi.disabled = true;
  btnSyncText.textContent = 'Lade Liste...';

  try {
    const listRes = await fetch(`http://${ip}/api/clips?t=${Date.now()}`, { cache: 'no-store' });
    if (!listRes.ok) throw new Error(`HTTP ${listRes.status}: ${listRes.statusText}`);

    const data = await listRes.json();
    const serverClips = data.clips || [];

    if (serverClips.length === 0) {
      alert('Der Flash-Speicher auf dem XIAO ist leer.\nHau auf das Breadboard, um eine Aufnahme zu machen!');
      btnSyncText.textContent = 'WLAN Synchronisieren';
      btnSyncWifi.disabled = false;
      return;
    }

    btnSyncText.textContent = `Lade ${serverClips.length} Clips...`;

    for (let i = 0; i < serverClips.length; ++i) {
      const clip = serverClips[i];
      const existing = synchronizedClips.find(c => c.id === clip.id);

      if (!existing) {
        const audioRes = await fetch(`http://${ip}/api/download?id=${clip.id}`, { cache: 'no-store' });
        if (audioRes.ok) {
          const blob = await audioRes.blob();
          const url = URL.createObjectURL(blob);
          synchronizedClips.unshift({
            id: clip.id,
            filename: clip.filename,
            duration: clip.duration,
            sizeKb: (blob.size / 1024).toFixed(1),
            blob: blob,
            url: url,
            time: new Date().toLocaleTimeString()
          });
        }
      }
    }

    renderClipsList();
    stateLabel.textContent = 'Synchronisation fertig!';
    stateDesc.textContent = `${serverClips.length} Aufnahme(n) erfolgreich vom Flash heruntergeladen.`;

    if (synchronizedClips.length > 0) {
      selectClip(synchronizedClips[0]);
    }

  } catch (err) {
    console.error('[Sync Error]', err);
    alert(`WLAN-Synchronisation fehlgeschlagen: ${err.message}\n\nStelle sicher, dass du mit dem WLAN "XIAO-Audio-Hotspot" (Passwort: xiaoesp32c3) verbunden bist!`);
  } finally {
    btnSyncWifi.disabled = false;
    btnSyncText.textContent = 'WLAN Synchronisieren';
  }
}

async function selectClip(clip) {
  currentActiveClipId = clip.id;
  currentWavBlob = clip.blob;
  currentWavUrl = clip.url;

  currentClipTitle.textContent = `Aufnahme #${clip.id} (${clip.filename})`;
  clipMetaEl.textContent = `${clip.duration.toFixed(1)}s • ${clip.sizeKb} KB • Dual-Mic Filter (Mono 8 KB/s)`;

  if (!audioContext) {
    audioContext = new (window.AudioContext || window.webkitAudioContext)();
  }

  const arrayBuffer = await currentWavBlob.arrayBuffer();
  
  // Decompress Mono IMA-ADPCM
  const decoded = decodeMonoImaAdpcm(arrayBuffer);
  rawMonoPcm = decoded.pcm;

  emptyWaveformMessage.style.display = 'none';
  btnPlay.disabled = false;
  btnDownload.disabled = false;

  applyAudioEffects();
  renderClipsList();
  startPlayback();
}

function renderClipsList() {
  if (synchronizedClips.length === 0) {
    clipsList.innerHTML = '<div class="no-clips-msg">Noch keine Aufnahmen synchronisiert. Klicke oben auf "WLAN Synchronisieren".</div>';
    return;
  }

  clipsList.innerHTML = '';
  synchronizedClips.forEach(clip => {
    const isSelected = clip.id === currentActiveClipId;
    const item = document.createElement('div');
    item.className = `clip-item ${isSelected ? 'selected' : ''}`;
    item.style.border = isSelected ? '1px solid var(--accent-cyan)' : '1px solid var(--border-color)';
    item.innerHTML = `
      <div class="clip-info" onclick="selectClipById(${clip.id})" style="cursor:pointer;flex:1;">
        <span class="clip-title" style="${isSelected ? 'color:var(--accent-cyan);' : ''}">Aufnahme #${clip.id}</span>
        <span class="clip-sub">${clip.duration.toFixed(1)}s • ${clip.sizeKb} KB (8 KB/s) • Synced ${clip.time}</span>
      </div>
      <div class="clip-actions">
        <button class="btn-icon-small" onclick="selectClipById(${clip.id})">▶ Anhören</button>
        <button class="btn-icon-small" onclick="downloadClipDirect(${clip.id})">⬇ WAV</button>
      </div>
    `;
    clipsList.appendChild(item);
  });
}

function selectClipById(id) {
  const clip = synchronizedClips.find(c => c.id === id);
  if (clip) selectClip(clip);
}

async function downloadClipDirect(id) {
  const clip = synchronizedClips.find(c => c.id === id);
  if (!clip) return;

  try {
    const arrayBuffer = await clip.blob.arrayBuffer();
    const decoded = decodeMonoImaAdpcm(arrayBuffer);
    
    if (!audioContext) {
      audioContext = new (window.AudioContext || window.webkitAudioContext)();
    }

    const buf = audioContext.createBuffer(1, decoded.numSamples, 16000);
    const ch0 = buf.getChannelData(0);
    for (let i = 0; i < decoded.numSamples; i++) {
      ch0[i] = decoded.pcm[i] / 32768.0;
    }

    const pcmBlob = audioBufferToPcmWavBlob(buf);
    const url = URL.createObjectURL(pcmBlob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `clip_${clip.id}_pcm16.wav`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    setTimeout(() => URL.revokeObjectURL(url), 8000);
  } catch (e) {
    console.error('Download error:', e);
  }
}

async function clearDeviceFlashStorage() {
  if (!confirm('Möchtest du wirklich ALLE gespeicherten Sprachaufnahmen vom 4MB Flash-Speicher des XIAO löschen?')) {
    return;
  }

  const ip = wifiIpInput.value.trim() || '192.168.4.1';
  try {
    const res = await fetch(`http://${ip}/api/clear`, { method: 'POST' });
    if (res.ok) {
      alert('Der Flash-Speicher auf dem XIAO wurde vollständig geleert!');
      synchronizedClips = [];
      renderClipsList();
    } else {
      throw new Error(`HTTP ${res.status}`);
    }
  } catch (err) {
    alert(`Löschen fehlgeschlagen: ${err.message}\nVerbinde dich mit dem WLAN "XIAO-Audio-Hotspot".`);
  }
}

function clearHistory() {
  synchronizedClips = [];
  renderClipsList();
}

// ============================================================================
// Waveform Drawing (HTML5 Canvas)
// ============================================================================
function drawWaveform(pcmData, playbackProgress = 0) {
  const canvas = waveformCanvas;
  const ctx = canvas.getContext('2d');
  const dpr = window.devicePixelRatio || 1;
  
  canvas.width = canvas.parentElement.clientWidth * dpr;
  canvas.height = canvas.parentElement.clientHeight * dpr;
  ctx.scale(dpr, dpr);

  const width = canvas.parentElement.clientWidth;
  const height = canvas.parentElement.clientHeight;

  ctx.clearRect(0, 0, width, height);

  const numBars = 75;
  const step = Math.floor(pcmData.length / numBars);
  const barWidth = (width / numBars) * 0.65;
  const gap = (width / numBars) * 0.35;

  const currentPlayIndex = Math.floor(playbackProgress * numBars);

  for (let i = 0; i < numBars; i++) {
    let sum = 0;
    for (let j = 0; j < step; j++) {
      sum += Math.abs(pcmData[i * step + j] || 0);
    }
    const avg = sum / step;
    const normalized = Math.min(1, avg / 12000);
    const barHeight = Math.max(4, normalized * (height * 0.82));

    const x = i * (barWidth + gap);
    const y = (height - barHeight) / 2;

    if (i <= currentPlayIndex && isPlaying) {
      ctx.fillStyle = '#06b6d4';
    } else {
      ctx.fillStyle = '#273549';
    }

    ctx.beginPath();
    ctx.roundRect(x, y, barWidth, barHeight, 3);
    ctx.fill();
  }
}

// ============================================================================
// Web Audio Player Controls
// ============================================================================
function togglePlayAudio() {
  if (isPlaying) {
    pausePlayback();
  } else {
    startPlayback(playbackOffset);
  }
}

function startPlayback(offset = 0) {
  if (!currentAudioBuffer || !audioContext) return;

  if (audioContext.state === 'suspended') {
    audioContext.resume();
  }

  stopSourceNode();

  currentSourceNode = audioContext.createBufferSource();
  currentSourceNode.buffer = currentAudioBuffer;
  currentSourceNode.connect(audioContext.destination);

  playbackOffset = offset;
  playbackStartTime = audioContext.currentTime - playbackOffset;

  currentSourceNode.start(0, playbackOffset);
  isPlaying = true;
  updatePlayButtonUI(true);

  currentSourceNode.onended = () => {
    if (isPlaying && (audioContext.currentTime - playbackStartTime >= currentAudioBuffer.duration)) {
      isPlaying = false;
      playbackOffset = 0;
      updatePlayButtonUI(false);
      seekSlider.value = 0;
      currentTimeEl.textContent = '0:00';
    }
  };

  trackPlaybackProgress();
}

function pausePlayback() {
  if (!isPlaying) return;
  playbackOffset = audioContext.currentTime - playbackStartTime;
  stopSourceNode();
  isPlaying = false;
  updatePlayButtonUI(false);
  if (animationFrameId) cancelAnimationFrame(animationFrameId);
}

function stopSourceNode() {
  if (currentSourceNode) {
    try { currentSourceNode.stop(); } catch (e) {}
    currentSourceNode.disconnect();
    currentSourceNode = null;
  }
}

function seekAudio(value) {
  const seekTime = parseFloat(value);
  playbackOffset = seekTime;
  currentTimeEl.textContent = formatTime(seekTime);
  if (isPlaying) {
    startPlayback(seekTime);
  }
}

function trackPlaybackProgress() {
  if (!isPlaying || !currentAudioBuffer) return;

  const current = audioContext.currentTime - playbackStartTime;
  const duration = currentAudioBuffer.duration;

  if (current <= duration) {
    seekSlider.value = current;
    currentTimeEl.textContent = formatTime(current);

    if (currentAudioBuffer) {
      const pcm = currentAudioBuffer.getChannelData(0);
      const int16 = new Int16Array(pcm.length);
      for (let i = 0; i < pcm.length; i++) int16[i] = pcm[i] * 32767;
      drawWaveform(int16, current / duration);
    }

    animationFrameId = requestAnimationFrame(trackPlaybackProgress);
  }
}

function updatePlayButtonUI(playing) {
  if (playing) {
    btnPlayText.textContent = 'Pause';
    playIcon.innerHTML = '<rect x="6" y="4" width="4" height="16"></rect><rect x="14" y="4" width="4" height="16"></rect>';
  } else {
    btnPlayText.textContent = 'Abspielen';
    playIcon.innerHTML = '<polygon points="5 3 19 12 5 21 5 3"></polygon>';
  }
}

function downloadCurrentClip() {
  if (!currentAudioBuffer) return;
  const pcmBlob = audioBufferToPcmWavBlob(currentAudioBuffer);
  const url = URL.createObjectURL(pcmBlob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `clip_${currentActiveClipId || 'recording'}_clean_pcm16.wav`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 8000);
}

function formatTime(seconds) {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s < 10 ? '0' : ''}${s}`;
}
