// ============================================================================
// BLE & Web Serial UUIDs / Constants
// ============================================================================
const BLE_SERVICE_UUID     = '19b10000-e8f2-537e-4f6c-d104768a1214';
const BLE_CHAR_STATE_UUID  = '19b10001-e8f2-537e-4f6c-d104768a1214';
const BLE_CHAR_AUDIO_UUID  = '19b10002-e8f2-537e-4f6c-d104768a1214';
const BLE_CHAR_TAP_UUID    = '19b10003-e8f2-537e-4f6c-d104768a1214';

// App State
let bleDevice = null;
let gattServer = null;
let charState = null;
let charAudio = null;
let charTap = null;

let incomingChunks = [];
let expectedTotalChunks = 0;
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
const transferContainer = document.getElementById('transferContainer');
const transferBar = document.getElementById('transferBar');
const transferPercent = document.getElementById('transferPercent');
const tapPulse = document.getElementById('tapPulse');
const tapText = document.getElementById('tapText');
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
// Robust Web Bluetooth Connection Handler (Windows Compatible)
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
    alert('Web Bluetooth wird in diesem Browser nicht unterstützt. Bitte nutze Google Chrome oder Microsoft Edge.');
    return;
  }

  try {
    btnConnectText.textContent = 'Suche Gerät...';
    
    bleDevice = await navigator.bluetooth.requestDevice({
      filters: [{ name: 'XIAO-Audio-Recorder' }],
      optionalServices: [BLE_SERVICE_UUID]
    });

    bleDevice.addEventListener('gattserverdisconnected', onDisconnected);

    btnConnectText.textContent = 'Verbinde GATT...';
    console.log('[BLE] Requesting GATT connection...');
    
    gattServer = await bleDevice.gatt.connect();

    // Windows Bluetooth stack stabilization delay
    await new Promise(r => setTimeout(r, 600));

    btnConnectText.textContent = 'Lade Services...';

    // Retrieve Primary Service with retry for Windows GATT handshake
    let service = null;
    for (let attempt = 1; attempt <= 3; attempt++) {
      try {
        if (!bleDevice.gatt.connected) {
          console.log(`[BLE] Reconnecting before service query (attempt ${attempt})...`);
          gattServer = await bleDevice.gatt.connect();
          await new Promise(r => setTimeout(r, 500));
        }
        service = await gattServer.getPrimaryService(BLE_SERVICE_UUID);
        break;
      } catch (err) {
        console.warn(`[BLE] Service query attempt ${attempt} failed:`, err);
        if (attempt === 3) throw err;
        await new Promise(r => setTimeout(r, 800));
      }
    }

    console.log('[BLE] Service discovered. Fetching characteristics...');

    // State Characteristic
    charState = await service.getCharacteristic(BLE_CHAR_STATE_UUID);
    await charState.startNotifications();
    charState.addEventListener('characteristicvaluechanged', onStateChanged);

    // Audio Characteristic
    charAudio = await service.getCharacteristic(BLE_CHAR_AUDIO_UUID);
    await charAudio.startNotifications();
    charAudio.addEventListener('characteristicvaluechanged', onAudioChunkReceived);

    // Tap Characteristic
    charTap = await service.getCharacteristic(BLE_CHAR_TAP_UUID);
    await charTap.startNotifications();
    charTap.addEventListener('characteristicvaluechanged', onTapEvent);

    // Update UI for Connected State
    btnConnect.classList.add('connected');
    btnConnectText.textContent = 'Trennen';
    connectionBadge.textContent = 'Verbunden (BLE)';
    connectionBadge.className = 'badge badge-connected';
    
    updateDeviceState(0); // IDLE
    console.log('[BLE] Successfully connected & subscribed to all characteristics!');

  } catch (err) {
    console.error('[BLE Connection Error]', err);
    btnConnectText.textContent = 'Mit XIAO verbinden';
    if (err.name !== 'NotFoundError') {
      alert(`Verbindungsfehler: ${err.message}\n\nHinweis: Falls Windows zickt, kopple das Gerät einmal in Windows-Einstellungen > Bluetooth oder schalte Bluetooth kurz aus/ein.`);
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
  btnConnectText.textContent = 'Mit XIAO verbinden';
  connectionBadge.textContent = 'Getrennt';
  connectionBadge.className = 'badge badge-disconnected';
  
  stateRing.className = 'state-ring state-idle';
  stateLabel.textContent = 'Getrennt';
  stateDesc.textContent = 'Klicke auf Verbinden, um Sprachaufnahmen per Erschütterung zu empfangen.';
  transferContainer.classList.add('hidden');
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
}

function updateDeviceState(state, totalBytes = 0) {
  stateRing.className = 'state-ring';

  switch (state) {
    case 0: // IDLE / BEREIT
      stateRing.classList.add('state-idle');
      stateLabel.textContent = 'Bereit zum Aufnehmen';
      stateDesc.textContent = 'Hau auf das Breadboard, um eine Aufnahme zu starten (LED leuchtet).';
      transferContainer.classList.add('hidden');
      break;

    case 1: // RECORDING
      stateRing.classList.add('state-recording');
      stateLabel.textContent = 'Aufnahme läuft...';
      stateDesc.textContent = 'Sprich jetzt ins Mikrofon! Hau nochmals auf das Breadboard zum Beenden & Senden.';
      transferContainer.classList.add('hidden');
      incomingChunks = [];
      break;

    case 2: // TRANSFERRING
      stateRing.classList.add('state-transferring');
      stateLabel.textContent = 'Übertrage Sprachaufnahme...';
      stateDesc.textContent = 'Empfange Audiodaten über Bluetooth Low Energy.';
      transferContainer.classList.remove('hidden');
      transferBar.style.width = '0%';
      transferPercent.textContent = '0%';
      break;

    case 3: // DONE
      stateRing.classList.add('state-idle');
      stateLabel.textContent = 'Aufnahme empfangen!';
      stateDesc.textContent = 'Die Sprachaufnahme wurde erfolgreich empfangen und kann abgespielt werden.';
      transferContainer.classList.add('hidden');
      break;
  }
}

function onTapEvent(event) {
  const data = event.target.value;
  if (data.byteLength >= 5) {
    const shockRaw = data.getInt32(1, true);
    const shockG = (shockRaw / 1000.0).toFixed(2);
    
    // Trigger Visual Pulse
    tapPulse.classList.add('active');
    tapText.textContent = `Tap! (${shockG}g)`;
    
    setTimeout(() => {
      tapPulse.classList.remove('active');
      tapText.textContent = 'Ruhe';
    }, 400);
  }
}

function onAudioChunkReceived(event) {
  const data = event.target.value;
  if (data.byteLength < 6) return;

  const chunkIdx = data.getUint16(0, true);
  const totalChunks = data.getUint16(2, true);
  const payloadLen = data.getUint16(4, true);

  expectedTotalChunks = totalChunks;

  // Extract raw payload bytes
  const payload = new Uint8Array(data.buffer, 6, payloadLen);
  incomingChunks[chunkIdx] = payload;

  // Update Progress Bar
  const receivedCount = incomingChunks.filter(Boolean).length;
  const pct = Math.min(100, Math.round((receivedCount / totalChunks) * 100));
  transferBar.style.width = pct + '%';
  transferPercent.textContent = pct + '%';

  if (receivedCount === totalChunks) {
    console.log(`[BLE Audio] All ${totalChunks} chunks received successfully! Assembling WAV...`);
    assembleAndProcessAudio();
  }
}

// ============================================================================
// Audio Reconstruction & Waveform Processing
// ============================================================================
async function assembleAndProcessAudio() {
  let totalBytes = 0;
  for (const chunk of incomingChunks) {
    if (chunk) totalBytes += chunk.byteLength;
  }

  if (totalBytes === 0) return;

  const mergedBuffer = new Uint8Array(totalBytes);
  let offset = 0;
  for (let i = 0; i < expectedTotalChunks; ++i) {
    if (incomingChunks[i]) {
      mergedBuffer.set(incomingChunks[i], offset);
      offset += incomingChunks[i].byteLength;
    }
  }

  // Convert to Int16Array (16-bit Mono PCM)
  const pcm16 = new Int16Array(mergedBuffer.buffer, mergedBuffer.byteOffset, mergedBuffer.byteLength / 2);
  
  // Create WAV File Blob
  currentWavBlob = createWavBlob(pcm16, currentSampleRate);
  if (currentWavUrl) URL.revokeObjectURL(currentWavUrl);
  currentWavUrl = URL.createObjectURL(currentWavBlob);

  // Initialize Web Audio Context if needed
  if (!audioContext) {
    audioContext = new (window.AudioContext || window.webkitAudioContext)();
  }

  const arrayBuffer = await currentWavBlob.arrayBuffer();
  currentAudioBuffer = await audioContext.decodeAudioData(arrayBuffer);

  // Update UI & Render Waveform
  emptyWaveformMessage.style.display = 'none';
  btnPlay.disabled = false;
  btnDownload.disabled = false;

  const durationSec = currentAudioBuffer.duration;
  totalTimeEl.textContent = formatTime(durationSec);
  currentTimeEl.textContent = '0:00';
  seekSlider.value = 0;
  seekSlider.max = durationSec;

  clipMetaEl.textContent = `${durationSec.toFixed(1)}s • ${currentSampleRate / 1000} kHz • ${(totalBytes / 1024).toFixed(1)} KB`;

  drawWaveform(pcm16);

  // Add to History
  addClipToHistory(currentWavBlob, durationSec);

  // Auto-play preview
  startPlayback();
}

function createWavBlob(pcmData, sampleRate) {
  const numChannels = 1;
  const bitsPerSample = 16;
  const byteRate = (sampleRate * numChannels * bitsPerSample) / 8;
  const blockAlign = (numChannels * bitsPerSample) / 8;
  const dataSize = pcmData.length * 2;
  const buffer = new ArrayBuffer(44 + dataSize);
  const view = new DataView(buffer);

  // RIFF Header
  writeString(view, 0, 'RIFF');
  view.setUint32(4, 36 + dataSize, true);
  writeString(view, 8, 'WAVE');

  // fmt subchunk
  writeString(view, 12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true); // PCM format
  view.setUint16(22, numChannels, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, byteRate, true);
  view.setUint16(32, blockAlign, true);
  view.setUint16(34, bitsPerSample, true);

  // data subchunk
  writeString(view, 36, 'data');
  view.setUint32(40, dataSize, true);

  // Write PCM Samples
  let offset = 44;
  for (let i = 0; i < pcmData.length; ++i) {
    view.setInt16(offset, pcmData[i], true);
    offset += 2;
  }

  return new Blob([view], { type: 'audio/wav' });
}

function writeString(view, offset, string) {
  for (let i = 0; i < string.length; i++) {
    view.setUint8(offset + i, string.charCodeAt(i));
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
      ctx.fillStyle = '#06b6d4'; // Active playback cyan
    } else {
      ctx.fillStyle = '#273549'; // Muted dark blue
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

    // Update Waveform
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
function addClipToHistory(blob, duration) {
  const clip = {
    id: Date.now(),
    time: new Date().toLocaleTimeString(),
    duration: duration.toFixed(1),
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
        <span class="clip-sub">${clip.duration} Sekunden • 16 kHz WAV</span>
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
