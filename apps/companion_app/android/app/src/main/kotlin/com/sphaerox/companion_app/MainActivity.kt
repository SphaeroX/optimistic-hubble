package com.sphaerox.companion_app

import android.bluetooth.BluetoothManager
import android.content.Context
import android.net.Network
import android.os.Build
import android.util.Log
import androidx.annotation.NonNull
import com.sphaerox.companion_app.ble.BleL2capAudioReceiver
import com.sphaerox.companion_app.network.IotHttpClientFactory
import com.sphaerox.companion_app.network.IotHotspotManager
import com.sphaerox.companion_app.network.IotWifiManager
import com.sphaerox.companion_app.network.WifiConnectionState
import com.sphaerox.companion_app.service.AudioSyncForegroundService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.Locale

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.sphaerox.companion_app/audio_sync"
    private val EVENT_CHANNEL = "com.sphaerox.companion_app/sync_events"

    private var eventSink: EventChannel.EventSink? = null
    private val activityScope = CoroutineScope(Dispatchers.Main + Job())
    private var activeSyncJob: Job? = null
    private var iotWifiManager: IotWifiManager? = null
    private var iotHotspotManager: IotHotspotManager? = null

    private fun getWifiManager(): IotWifiManager {
        var manager = iotWifiManager
        if (manager == null) {
            manager = IotWifiManager(applicationContext)
            iotWifiManager = manager
        }
        return manager
    }

    private fun getHotspotManager(): IotHotspotManager {
        var manager = iotHotspotManager
        if (manager == null) {
            manager = IotHotspotManager(applicationContext)
            iotHotspotManager = manager
        }
        return manager
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        try {
            iotWifiManager = IotWifiManager(applicationContext)
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to initialize IotWifiManager: ${e.message}", e)
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "isNativeSupported" -> {
                            result.success(true)
                        }

                        "isL2capSupported" -> {
                            result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                        }

                        "startLocalOnlyHotspot" -> {
                            val port = call.argument<Int>("port") ?: 8080
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                                result.error("UNSUPPORTED", "Local-Only Hotspot requires Android 8.0+ (API 26)", null)
                                return@setMethodCallHandler
                            }

                            activityScope.launch(Dispatchers.IO) {
                                val hotspotManager = getHotspotManager()
                                try {
                                    val creds = hotspotManager.startHotspot(port)
                                    withContext(Dispatchers.Main) {
                                        result.success(mapOf(
                                            "ssid" to creds.ssid,
                                            "passphrase" to creds.passphrase,
                                            "ip" to creds.ip,
                                            "port" to creds.port
                                        ))
                                    }
                                } catch (e: Exception) {
                                    withContext(Dispatchers.Main) {
                                        result.error("HOTSPOT_START_FAILED", e.message ?: "Failed to start Local-Only Hotspot", null)
                                    }
                                }
                            }
                        }

                        "stopLocalOnlyHotspot" -> {
                            try {
                                getHotspotManager().stopHotspot()
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("HOTSPOT_STOP_FAILED", e.message, null)
                            }
                        }

                        "isHotspotActive" -> {
                            result.success(getHotspotManager().isHotspotActive())
                        }

                        "startBleL2capSync" -> {
                            val deviceAddress = call.argument<String>("deviceAddress")
                            val fileId = call.argument<Number>("fileId")?.toLong() ?: 0L
                            val psm = call.argument<Int>("psm") ?: 0x0081
                            val destinationPath = call.argument<String>("destinationPath")

                            if (deviceAddress.isNullOrEmpty()) {
                                result.error("INVALID_ARGS", "Device address is required", null)
                                return@setMethodCallHandler
                            }

                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                                result.error("UNSUPPORTED", "L2CAP requires Android 10+ (API 29)", null)
                                return@setMethodCallHandler
                            }

                            startBleL2capSync(deviceAddress, fileId, psm, destinationPath, result)
                        }

                        "connectWifiSoftAp" -> {
                            val ssidPattern = call.argument<String>("ssidPattern") ?: "Audio-Vault-Hotspot"
                            val passphrase = call.argument<String>("passphrase") ?: "audiovault2026"

                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                                result.error("UNSUPPORTED", "WifiNetworkSpecifier requires Android 10+", null)
                                return@setMethodCallHandler
                            }

                            activityScope.launch(Dispatchers.IO) {
                                val wifiManager = getWifiManager()
                                try {
                                    wifiManager.connect(ssidPattern, passphrase)
                                    withContext(Dispatchers.Main) {
                                        result.success(true)
                                    }
                                } catch (e: Exception) {
                                    withContext(Dispatchers.Main) {
                                        result.error("WIFI_CONNECT_FAILED", e.message ?: "Failed to connect to SoftAP", null)
                                    }
                                }
                            }
                        }

                        "disconnectWifiSoftAp" -> {
                            try {
                                getWifiManager().disconnect()
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("WIFI_DISCONNECT_FAILED", e.message, null)
                            }
                        }

                        "isWifiConnected" -> {
                            result.success(getWifiManager().isConnected())
                        }

                        "startWifiSoftApSync" -> {
                            val ssidPattern = call.argument<String>("ssidPattern") ?: "Audio-Vault-Hotspot"
                            val passphrase = call.argument<String>("passphrase") ?: "audiovault2026"
                            val fileId = call.argument<Number>("fileId")?.toLong() ?: 0L
                            val startOffset = call.argument<Number>("startOffset")?.toLong() ?: 0L
                            val destinationPath = call.argument<String>("destinationPath")
                            val keepConnected = call.argument<Boolean>("keepConnected") ?: false
                            val deleteAfterSync = call.argument<Boolean>("deleteAfterSync") ?: false

                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                                result.error("UNSUPPORTED", "WifiNetworkSpecifier requires Android 10+", null)
                                return@setMethodCallHandler
                            }

                            startWifiSoftApSync(ssidPattern, passphrase, fileId, startOffset, destinationPath, keepConnected, deleteAfterSync, result)
                        }

                        "performHandshake" -> {
                            activityScope.launch(Dispatchers.IO) {
                                try {
                                    val wifiManager = getWifiManager()
                                    val activeNet = wifiManager.getActiveNetwork()
                                    if (activeNet == null) {
                                        withContext(Dispatchers.Main) {
                                            result.error("NOT_CONNECTED", "Wi-Fi not connected to ESP32", null)
                                        }
                                        return@launch
                                    }
                                    val client = IotHttpClientFactory.createClient(activeNet)
                                    val req = Request.Builder().url("http://192.168.4.1/api/handshake").build()
                                    client.newCall(req).execute().use { response ->
                                        val body = response.body?.string() ?: "{}"
                                        withContext(Dispatchers.Main) {
                                            result.success(body)
                                        }
                                    }
                                } catch (e: Exception) {
                                    withContext(Dispatchers.Main) {
                                        result.error("HANDSHAKE_FAILED", e.message, null)
                                    }
                                }
                            }
                        }

                        "deleteRemoteClip" -> {
                            val fileId = call.argument<Number>("fileId")?.toLong() ?: 0L
                            activityScope.launch(Dispatchers.IO) {
                                try {
                                    val wifiManager = getWifiManager()
                                    val activeNet = wifiManager.getActiveNetwork()
                                    if (activeNet == null) {
                                        withContext(Dispatchers.Main) {
                                            result.error("NOT_CONNECTED", "Wi-Fi not connected to ESP32", null)
                                        }
                                        return@launch
                                    }
                                    val client = IotHttpClientFactory.createClient(activeNet)
                                    val req = Request.Builder()
                                        .url("http://192.168.4.1/api/delete?id=$fileId")
                                        .post(okhttp3.RequestBody.create(null, ByteArray(0)))
                                        .build()
                                    client.newCall(req).execute().use { response ->
                                        val success = response.isSuccessful
                                        withContext(Dispatchers.Main) {
                                            result.success(success)
                                        }
                                    }
                                } catch (e: Exception) {
                                    withContext(Dispatchers.Main) {
                                        result.error("DELETE_FAILED", e.message, null)
                                    }
                                }
                            }
                        }

                        "cancelSync" -> {
                            activeSyncJob?.cancel()
                            try { getWifiManager().disconnect() } catch (_: Throwable) {}
                            sendEvent("cancelled", 0.0, 0, 0, "Sync cancelled by user")
                            result.success(true)
                        }

                        else -> {
                            result.notImplemented()
                        }
                    }
                } catch (e: Throwable) {
                    Log.e(TAG, "Unhandled method call exception: ${e.message}", e)
                    result.error("EXCEPTION", e.message, null)
                }
            }
    }

    private fun startBleL2capSync(
        deviceAddress: String,
        fileId: Long,
        psm: Int,
        destinationPath: String?,
        result: MethodChannel.Result
    ) {
        activeSyncJob?.cancel()
        activeSyncJob = activityScope.launch(Dispatchers.IO) {
            val targetFile = if (!destinationPath.isNullOrEmpty()) {
                File(destinationPath).also { it.parentFile?.mkdirs() }
            } else {
                File(filesDir, "clip_${fileId}.wav")
            }
            try {
                sendEvent("connecting", 0.0, 0, 0, "Opening L2CAP channel (PSM 0x${psm.toString(16)})...")

                val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                val adapter = btManager?.adapter ?: throw IOException("Bluetooth Adapter unavailable")
                val device = adapter.getRemoteDevice(deviceAddress)
                val receiver = BleL2capAudioReceiver(applicationContext)

                val startTime = System.currentTimeMillis()

                val success = receiver.receiveAudioViaL2cap(
                    device = device,
                    psm = psm,
                    outputFile = targetFile,
                    onConnected = {
                        sendEvent("connected", 0.05, 0, 0, "L2CAP channel connected! Streaming audio...")
                    }
                ) { bytesReceived, totalBytes ->
                    if (!isActive) throw CancellationException("BLE L2CAP sync cancelled")
                    val elapsedSec = (System.currentTimeMillis() - startTime) / 1000.0
                    val speedKb = if (elapsedSec > 0) (bytesReceived / 1024.0) / elapsedSec else 0.0
                    val progress = if (totalBytes > 0) (bytesReceived.toDouble() / totalBytes.toDouble()).coerceIn(0.0, 1.0) else 0.0

                    sendEvent(
                        status = "transferring",
                        progress = progress,
                        bytesReceived = bytesReceived,
                        totalBytes = totalBytes,
                        message = "${String.format(Locale.US, "%.1f", speedKb)} KB/s (BLE 5.0 High-Throughput)",
                        filePath = targetFile.absolutePath
                    )
                }

                if (!isActive) return@launch

                withContext(Dispatchers.Main) {
                    if (success) {
                        sendEvent("completed", 1.0, targetFile.length(), targetFile.length(), "Sync complete", targetFile.absolutePath)
                        result.success(targetFile.absolutePath)
                    } else {
                        sendEvent("failed", 0.0, 0, 0, "L2CAP sync failed or CRC mismatch")
                        result.error("SYNC_FAILED", "L2CAP audio transfer failed", null)
                    }
                }
            } catch (e: CancellationException) {
                Log.i(TAG, "startBleL2capSync cancelled")
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    sendEvent("failed", 0.0, 0, 0, e.message ?: "Unknown error")
                    result.error("ERROR", e.message, null)
                }
            }
        }
    }

    private fun startWifiSoftApSync(
        ssidPattern: String,
        passphrase: String,
        fileId: Long,
        startOffset: Long,
        destinationPath: String?,
        keepConnected: Boolean,
        deleteAfterSync: Boolean,
        result: MethodChannel.Result
    ) {
        activeSyncJob?.cancel()
        activeSyncJob = activityScope.launch(Dispatchers.IO) {
            val wifiManager = getWifiManager()
            val targetFile = if (!destinationPath.isNullOrEmpty()) {
                File(destinationPath).also { it.parentFile?.mkdirs() }
            } else {
                File(filesDir, if (fileId > 0) "clip_${fileId}.wav" else "clip_latest.wav")
            }
            val tempFile = File(targetFile.parentFile ?: filesDir, "${targetFile.name}.part")

            try {
                val activeNet = wifiManager.getActiveNetwork()
                val network: Network = if (wifiManager.isConnected() && activeNet != null) {
                    Log.i(TAG, "Reusing already active IoT Wi-Fi connection: $activeNet")
                    sendEvent("connected_wifi", 0.35, 0, 0, "Reusing active Wi-Fi connection")
                    activeNet
                } else {
                    sendEvent("connecting_wifi", 0.15, 0, 0, "Connecting to Audio Vault Hotspot...")
                    val net = wifiManager.connect(ssidPattern, passphrase)
                    sendEvent("connected_wifi", 0.35, 0, 0, "Wi-Fi link established!")
                    net
                }

                val client = IotHttpClientFactory.createClient(network)

                // Handshake step
                sendEvent("handshaking", 0.50, 0, 0, "Performing device handshake...")
                try {
                    val handshakeReq = Request.Builder().url("http://192.168.4.1/api/handshake").build()
                    client.newCall(handshakeReq).execute().use { hsResp ->
                        if (hsResp.isSuccessful) {
                            Log.i(TAG, "Handshake successful: ${hsResp.body?.string()}")
                        }
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "Handshake check non-fatal warning: ${e.message}")
                }

                sendEvent("ready", 0.65, 0, 0, "Device ready! Starting high-speed transfer...")

                val url = if (fileId > 0) "http://192.168.4.1/api/download?id=$fileId" else "http://192.168.4.1/api/download"
                
                val reqBuilder = Request.Builder().url(url)
                val effectiveStartOffset = if (startOffset > 0 && tempFile.exists() && tempFile.length() == startOffset) {
                    startOffset
                } else {
                    0L
                }

                if (effectiveStartOffset > 0) {
                    reqBuilder.addHeader("Range", "bytes=$effectiveStartOffset-")
                }

                client.newCall(reqBuilder.build()).execute().use { response ->
                    if (!response.isSuccessful && response.code != 206) {
                        throw IOException("Server returned HTTP ${response.code}")
                    }

                    val body = response.body ?: throw IOException("Empty response body")
                    val isPartial = (response.code == 206 && effectiveStartOffset > 0)
                    val actualStartOffset = if (isPartial) effectiveStartOffset else 0L
                    val totalLength = (response.header("Content-Length")?.toLongOrNull() ?: 0L) + actualStartOffset

                    var bytesReadTotal = actualStartOffset
                    val fos = FileOutputStream(tempFile, isPartial)
                    val buffer = ByteArray(16384)
                    val startTime = System.currentTimeMillis()

                    body.byteStream().use { input ->
                        fos.use { output ->
                            var read: Int
                            while (input.read(buffer).also { read = it } != -1) {
                                if (!isActive) {
                                    throw CancellationException("Download cancelled by user")
                                }
                                output.write(buffer, 0, read)
                                bytesReadTotal += read

                                val elapsedSec = (System.currentTimeMillis() - startTime) / 1000.0
                                val speedMb = if (elapsedSec > 0) ((bytesReadTotal - actualStartOffset) / (1024.0 * 1024.0)) / elapsedSec else 0.0
                                val progress = if (totalLength > 0) (bytesReadTotal.toDouble() / totalLength.toDouble()).coerceIn(0.0, 1.0) else 0.5

                                sendEvent(
                                    status = "transferring",
                                    progress = progress,
                                    bytesReceived = bytesReadTotal,
                                    totalBytes = totalLength,
                                    message = "${String.format(Locale.US, "%.2f", speedMb)} MB/s (Wi-Fi Fast Transfer)",
                                    filePath = targetFile.absolutePath
                                )
                            }
                        }
                    }
                }

                if (!isActive) return@launch

                if (targetFile.exists()) targetFile.delete()
                if (!tempFile.renameTo(targetFile)) {
                    tempFile.copyTo(targetFile, overwrite = true)
                    tempFile.delete()
                }

                if (deleteAfterSync && fileId > 0) {
                    try {
                        val delReq = Request.Builder()
                            .url("http://192.168.4.1/api/delete?id=$fileId")
                            .post(okhttp3.RequestBody.create(null, ByteArray(0)))
                            .build()
                        client.newCall(delReq).execute().close()
                        Log.i(TAG, "Successfully deleted remote clip #$fileId from ESP32 after sync")
                    } catch (e: Exception) {
                        Log.w(TAG, "Failed to auto-delete clip #$fileId after sync: ${e.message}")
                    }
                }

                if (!keepConnected) {
                    try { wifiManager.disconnect() } catch (_: Throwable) {}
                }

                withContext(Dispatchers.Main) {
                    sendEvent("completed", 1.0, targetFile.length(), targetFile.length(), "Sync complete", targetFile.absolutePath)
                    result.success(targetFile.absolutePath)
                }
            } catch (e: CancellationException) {
                Log.i(TAG, "startWifiSoftApSync cancelled")
                if (!keepConnected) {
                    try { getWifiManager().disconnect() } catch (_: Throwable) {}
                }
            } catch (e: Exception) {
                if (!keepConnected) {
                    try { getWifiManager().disconnect() } catch (_: Throwable) {}
                }
                withContext(Dispatchers.Main) {
                    sendEvent("failed", 0.0, 0, 0, e.message ?: "Unknown error")
                    result.error("ERROR", e.message, null)
                }
            }
        }
    }

    private fun sendEvent(
        status: String,
        progress: Double,
        bytesReceived: Long,
        totalBytes: Long,
        message: String,
        filePath: String? = null
    ) {
        activityScope.launch(Dispatchers.Main) {
            val event = mapOf(
                "status" to status,
                "progress" to progress,
                "bytesReceived" to bytesReceived,
                "totalBytes" to totalBytes,
                "message" to message,
                "filePath" to (filePath ?: "")
            )
            eventSink?.success(event)
        }
    }

    override fun onDestroy() {
        activeSyncJob?.cancel()
        activityScope.cancel()
        try { iotWifiManager?.disconnect() } catch (_: Throwable) {}
        try { iotHotspotManager?.stopHotspot() } catch (_: Throwable) {}
        super.onDestroy()
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}
