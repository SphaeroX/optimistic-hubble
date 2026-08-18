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
const flashStatus = document.getElementById('flashStatus');
const wifiIpInput = document.getElementById('wifiIpInput');
const btnSyncWifi = document.getElementById('btnSyncWifi');
const btnSyncText = document.getElementById('btnSyncText');
const currentClipTitle = document.getElementById('currentClipTitle');
const waveformCanvas = document.getElementById('waveformCanvas');
const emptyWaveformMessage = document.getElementById('emptyWaveformMessage');
const btnPlay = document.getElementById('btnPlay');
const btnPlayText = document.getElementById('btnPlayText');
const playIcon = document.getElementById('playIcon');
const btnDownload = document.getElementById('btnDownload');
const seekSlider = document.getElementById('seekSlider');
const currentTimeEl = document.getElementById('currentTime');
const totalTimeEl = document.getElementById('totalTime');
const clipMetaEl = document.getElementById('clipMeta');
const clipsList = document.getElementById('clipsList');

function getApiBaseUrl() {
  if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
    return ''; // Proxy through local server seamlessly
  }
  const ip = (wifiIpInput && wifiIpInput.value.trim()) || '192.168.4.1';
  return `http://${ip}`;
}

// ============================================================================
// BLE Live Signaling (Optional Background Link)
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
    alert('Web Bluetooth wird von diesem Browser nicht unterstützt. Du kannst alle Daten jederzeit über WLAN synchronisieren!');
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
      stateLabel.textContent = 'Aufnahme läuft...';
      stateDesc.textContent = 'Sprich ins Mikrofon! Hau nochmals auf das Breadboard zum Beenden & Speichern.';
      break;

    case 3: // DONE / SAVED_TO_FLASH
      stateRing.classList.add('state-idle');
      stateLabel.textContent = `Aufnahme #${latestClipId} im Flash gespeichert!`;
      stateDesc.textContent = `Gesamt ${totalClips} Aufnahme(n) im Flash bereit zur WLAN-Synchronisation.`;
      flashStatus.textContent = `${totalClips} Aufnahmen`;
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
  const base = getApiBaseUrl();
  btnSyncWifi.disabled = true;
  btnSyncText.textContent = 'Lade Liste...';

  try {
    const listRes = await fetch(`${base}/api/clips?t=${Date.now()}`, { cache: 'no-store' });
    if (!listRes.ok) throw new Error(`HTTP ${listRes.status}: ${listRes.statusText}`);

    const data = await listRes.json();
    if (data.error) throw new Error(data.error);

    const serverClips = data.clips || [];

    if (serverClips.length === 0) {
      alert('Der Flash-Speicher auf dem XIAO ist leer.\nHau auf das Breadboard, um eine Aufnahme zu machen!');
      btnSyncText.textContent = 'WLAN Synchronisieren';
      btnSyncWifi.disabled = false;
      return;
    }

    btnSyncText.textContent = `Lade ${serverClips.length} Clips...`;

    // Fetch all clips and store in local session
    for (let i = 0; i < serverClips.length; ++i) {
      const clip = serverClips[i];
      const existing = synchronizedClips.find(c => c.id === clip.id);

      if (!existing) {
        const audioRes = await fetch(`${base}/api/download?id=${clip.id}`, { cache: 'no-store' });
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
    flashStatus.textContent = `${serverClips.length} im Flash`;
    stateLabel.textContent = 'Synchronisation fertig!';
    stateDesc.textContent = `${serverClips.length} Aufnahme(n) erfolgreich heruntergeladen.`;

    // Select the latest clip
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
  clipMetaEl.textContent = `${clip.duration.toFixed(1)}s • ${clip.sizeKb} KB • 16 kHz WAV`;

  if (!audioContext) {
    audioContext = new (window.AudioContext || window.webkitAudioContext)();
  }

  const arrayBuffer = await currentWavBlob.arrayBuffer();
  currentAudioBuffer = await audioContext.decodeAudioData(arrayBuffer);

  emptyWaveformMessage.style.display = 'none';
  btnPlay.disabled = false;
  btnDownload.disabled = false;

  const duration = currentAudioBuffer.duration;
  totalTimeEl.textContent = formatTime(duration);
  currentTimeEl.textContent = '0:00';
  seekSlider.value = 0;
  seekSlider.max = duration;

  // Draw Waveform
  const pcmFloat = currentAudioBuffer.getChannelData(0);
  const pcm16 = new Int16Array(pcmFloat.length);
  for (let i = 0; i < pcmFloat.length; ++i) {
    pcm16[i] = pcmFloat[i] * 32767;
  }
  drawWaveform(pcm16);

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
        <span class="clip-sub">${clip.duration.toFixed(1)}s • ${clip.sizeKb} KB • Synced ${clip.time}</span>
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

function downloadClipDirect(id) {
  const clip = synchronizedClips.find(c => c.id === id);
  if (!clip) return;
  const a = document.createElement('a');
  a.href = clip.url;
  a.download = `clip_${clip.id}.wav`;
  a.click();
}

async function clearDeviceFlashStorage() {
  if (!confirm('Möchtest du wirklich ALLE gespeicherten Sprachaufnahmen vom 4MB Flash-Speicher des XIAO löschen?')) {
    return;
  }

  const base = getApiBaseUrl();
  try {
    const res = await fetch(`${base}/api/clear`, { method: 'POST' });
    if (res.ok) {
      alert('Der Flash-Speicher auf dem XIAO wurde vollständig geleert!');
      flashStatus.textContent = '0 im Flash';
      synchronizedClips = [];
      renderClipsList();
    } else {
      throw new Error(`HTTP ${res.status}`);
    }
  } catch (err) {
    alert(`Löschen fehlgeschlagen: ${err.message}`);
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

    const pcm = currentAudioBuffer.getChannelData(0);
    const int16 = new Int16Array(pcm.length);
    for (let i = 0; i < pcm.length; i++) int16[i] = pcm[i] * 32767;
    drawWaveform(int16, current / duration);

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
  if (!currentWavBlob) return;
  const a = document.createElement('a');
  a.href = currentWavUrl;
  a.download = `xiao_clip_${currentActiveClipId || 'rec'}.wav`;
  a.click();
}

function formatTime(seconds) {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s < 10 ? '0' : ''}${s}`;
}
