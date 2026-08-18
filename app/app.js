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

let currentSampleRate = 16000;
let currentWavBlob = null;
let currentWavUrl = null;
let audioContext = null;
let currentAudioBuffer = null;
let currentSourceNode = null;
let isPlaying = false;
let playbackStartTime = 0;
let playbackOffset = 0;
let animationFrameId = null;

let recordedClips = [];

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
const btnFetchWifi = document.getElementById('btnFetchWifi');
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

// ============================================================================
// BLE Connection Management
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
    alert('Web Bluetooth wird nicht unterstützt. Du kannst die Sprachaufnahme aber direkt über WLAN ("Von WLAN laden") abrufen!');
    return;
  }

  try {
    btnConnectText.textContent = 'Suche BLE...';
    
    bleDevice = await navigator.bluetooth.requestDevice({
      filters: [{ name: 'XIAO-Audio-Recorder' }],
      optionalServices: [BLE_SERVICE_UUID]
    });

    bleDevice.addEventListener('gattserverdisconnected', onDisconnected);

    btnConnectText.textContent = 'Verbinde...';
    gattServer = await bleDevice.gatt.connect();
    await new Promise(r => setTimeout(r, 600));

    let service = null;
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        if (!bleDevice.gatt.connected) {
          gattServer = await bleDevice.gatt.connect();
          await new Promise(r => setTimeout(r, 400));
        }
        service = await gattServer.getPrimaryService(BLE_SERVICE_UUID);
        break;
      } catch (err) {
        if (attempt === 3) throw err;
        await new Promise(r => setTimeout(r, 600));
      }
    }

    // State Characteristic
    charState = await service.getCharacteristic(BLE_CHAR_STATE_UUID);
    await charState.startNotifications();
    charState.addEventListener('characteristicvaluechanged', onStateChanged);

    // Tap Characteristic
    charTap = await service.getCharacteristic(BLE_CHAR_TAP_UUID);
    await charTap.startNotifications();
    charTap.addEventListener('characteristicvaluechanged', onTapEvent);

    // Update UI
    btnConnect.classList.add('connected');
    btnConnectText.textContent = 'Trennen';
    connectionBadge.textContent = 'BLE Verbunden';
    connectionBadge.className = 'badge badge-connected';
    
    updateDeviceState(0);
    console.log('[BLE] Connected. Signaling ready!');

  } catch (err) {
    console.error('[BLE Error]', err);
    btnConnectText.textContent = 'Mit BLE verbinden';
    if (err.name !== 'NotFoundError') {
      alert(`BLE-Hinweis: ${err.message}\nDu kannst das Audio auch ohne BLE direkt per Klick auf "Von WLAN laden" abrufen!`);
    }
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
  btnConnectText.textContent = 'Mit BLE verbinden';
  connectionBadge.textContent = 'BLE Getrennt';
  connectionBadge.className = 'badge badge-disconnected';
  
  stateRing.className = 'state-ring state-idle';
  stateLabel.textContent = 'Bereit';
  stateDesc.textContent = 'Hau auf das Breadboard zum Aufnehmen. Audio kann jederzeit über WLAN geladen werden.';
  console.log('[BLE] Disconnected.');
}

// ============================================================================
// BLE Notification Handlers
// ============================================================================
function onStateChanged(event) {
  const data = event.target.value;
  if (data.byteLength < 1) return;

  const state = data.getUint8(0);
  const totalBytes = data.byteLength >= 5 ? data.getUint32(1, true) : 0;
  const sampleRate = data.byteLength >= 7 ? data.getUint16(5, true) : 16000;

  if (sampleRate > 0) currentSampleRate = sampleRate;
  updateDeviceState(state, totalBytes);

  // When recording is finished (STATE_DONE), fetch instantly over Wi-Fi!
  if (state === 3) {
    console.log('[BLE] Received CLIP_READY signal! Fetching audio over Wi-Fi...');
    fetchAudioFromWifi(false);
  }
}

function updateDeviceState(state, totalBytes = 0) {
  stateRing.className = 'state-ring';

  switch (state) {
    case 0: // IDLE
      stateRing.classList.add('state-idle');
      stateLabel.textContent = 'Bereit zum Aufnehmen';
      stateDesc.textContent = 'Hau auf das Breadboard, um die Aufnahme zu starten (LED leuchtet).';
      break;

    case 1: // RECORDING
      stateRing.classList.add('state-recording');
      stateLabel.textContent = 'Aufnahme läuft...';
      stateDesc.textContent = 'Sprich jetzt ins Mikrofon! Hau nochmals auf das Breadboard zum Beenden.';
      break;

    case 3: // DONE / READY_ON_WIFI
      stateRing.classList.add('state-idle');
      stateLabel.textContent = 'Lade Audio über WLAN...';
      stateDesc.textContent = 'Empfange WAV-Audiodatei mit voller Geschwindigkeit (>2 MB/s)...';
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
// High-Speed Wi-Fi Audio Fetching (Sub-100ms)
// ============================================================================
async function fetchAudioFromWifi(showManualAlert = false) {
  const ip = wifiIpInput.value.trim() || '192.168.4.1';
  const url = `http://${ip}/audio.wav?t=${Date.now()}`;

  try {
    btnFetchWifi.disabled = true;
    btnFetchWifi.innerHTML = '<span>Lade...</span>';
    stateLabel.textContent = 'Übertrage via WLAN...';

    const startTime = performance.now();
    const response = await fetch(url, { cache: 'no-store' });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    currentWavBlob = await response.blob();
    const elapsedMs = Math.round(performance.now() - startTime);

    if (currentWavUrl) URL.revokeObjectURL(currentWavUrl);
    currentWavUrl = URL.createObjectURL(currentWavBlob);

    // Initialize Web Audio Context
    if (!audioContext) {
      audioContext = new (window.AudioContext || window.webkitAudioContext)();
    }

    const arrayBuffer = await currentWavBlob.arrayBuffer();
    currentAudioBuffer = await audioContext.decodeAudioData(arrayBuffer);

    // Update UI
    emptyWaveformMessage.style.display = 'none';
    btnPlay.disabled = false;
    btnDownload.disabled = false;

    const durationSec = currentAudioBuffer.duration;
    totalTimeEl.textContent = formatTime(durationSec);
    currentTimeEl.textContent = '0:00';
    seekSlider.value = 0;
    seekSlider.max = durationSec;

    clipMetaEl.textContent = `${durationSec.toFixed(1)}s • WLAN (${elapsedMs}ms) • ${(currentWavBlob.size / 1024).toFixed(1)} KB`;
    stateLabel.textContent = 'Aufnahme bereit!';
    stateDesc.textContent = `WLAN-Download in ${elapsedMs}ms abgeschlossen!`;

    // Draw Waveform
    const pcmFloat = currentAudioBuffer.getChannelData(0);
    const pcm16 = new Int16Array(pcmFloat.length);
    for (let i = 0; i < pcmFloat.length; ++i) {
      pcm16[i] = pcmFloat[i] * 32767;
    }
    drawWaveform(pcm16);

    // Add to History & Auto-play
    addClipToHistory(currentWavBlob, durationSec, elapsedMs);
    startPlayback();

    console.log(`[WIFI] Audio downloaded and decoded in ${elapsedMs}ms!`);

  } catch (err) {
    console.error('[WIFI Download Error]', err);
    stateLabel.textContent = 'WLAN-Download fehlgeschlagen';
    stateDesc.textContent = `Konnte http://${ip}/audio.wav nicht erreichen. Stelle sicher, dass du mit dem WLAN "XIAO-Audio-Hotspot" verbunden bist.`;
    
    if (showManualAlert) {
      alert(`WLAN-Fehler: Konnte http://${ip}/audio.wav nicht laden.\n\nPrüfe:\n1. Bist du mit dem WLAN-Hotspot "XIAO-Audio-Hotspot" (Passwort: xiaoesp32c3) verbunden?\n2. Hast du vorher auf das Breadboard gehauen, um eine Aufnahme zu machen?`);
    }
  } finally {
    btnFetchWifi.disabled = false;
    btnFetchWifi.innerHTML = '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M5 12.55a11 11 0 0 1 14.08 0"></path><path d="M1.42 9a16 16 0 0 1 21.16 0"></path><path d="M8.53 16.11a6 6 0 0 1 6.95 0"></path><line x1="12" y1="20" x2="12.01" y2="20"></line></svg><span>Von WLAN laden</span>';
  }
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
  const dateStr = new Date().toISOString().slice(11, 19).replace(/:/g, '-');
  a.download = `xiao_recording_${dateStr}.wav`;
  a.click();
}

function formatTime(seconds) {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${s < 10 ? '0' : ''}${s}`;
}

// ============================================================================
// History Management
// ============================================================================
function addClipToHistory(blob, duration, ms = 50) {
  const clip = {
    id: Date.now(),
    time: new Date().toLocaleTimeString(),
    duration: duration.toFixed(1),
    speed: ms,
    blob: blob,
    url: URL.createObjectURL(blob)
  };
  recordedClips.unshift(clip);
  renderHistory();
}

function renderHistory() {
  if (recordedClips.length === 0) {
    clipsList.innerHTML = '<div class="no-clips-msg">Noch keine Aufnahmen empfangen.</div>';
    return;
  }

  clipsList.innerHTML = '';
  recordedClips.forEach(clip => {
    const item = document.createElement('div');
    item.className = 'clip-item';
    item.innerHTML = `
      <div class="clip-info">
        <span class="clip-title">Aufnahme um ${clip.time}</span>
        <span class="clip-sub">${clip.duration}s • WLAN (${clip.speed}ms) • 16 kHz WAV</span>
      </div>
      <div class="clip-actions">
        <button class="btn-icon-small" onclick="playHistoryClip('${clip.url}')">▶ Play</button>
        <button class="btn-icon-small" onclick="downloadHistoryClip('${clip.url}', '${clip.time}')">⬇ WAV</button>
      </div>
    `;
    clipsList.appendChild(item);
  });
}

function playHistoryClip(url) {
  const audio = new Audio(url);
  audio.play();
}

function downloadHistoryClip(url, time) {
  const a = document.createElement('a');
  a.href = url;
  a.download = `recording_${time.replace(/:/g, '-')}.wav`;
  a.click();
}

function clearHistory() {
  recordedClips = [];
  renderHistory();
}
