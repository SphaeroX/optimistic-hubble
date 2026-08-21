package com.sphaerox.companion_app

import android.bluetooth.BluetoothManager
import android.content.Context
import android.net.Network
import android.os.Build
import android.util.Log
import androidx.annotation.NonNull
import com.sphaerox.companion_app.ble.BleL2capAudioReceiver
import com.sphaerox.companion_app.network.IotHttpClientFactory
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

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.sphaerox.companion_app/audio_sync"
    private val EVENT_CHANNEL = "com.sphaerox.companion_app/sync_events"

    private var eventSink: EventChannel.EventSink? = null
    private val activityScope = CoroutineScope(Dispatchers.Main + Job())
    private var activeSyncJob: Job? = null
    private var iotWifiManager: IotWifiManager? = null

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

                        "startBleL2capSync" -> {
                            val deviceAddress = call.argument<String>("deviceAddress")
                            val fileId = call.argument<Number>("fileId")?.toLong() ?: 0L
                            val psm = call.argument<Int>("psm") ?: 0x0081

                            if (deviceAddress.isNullOrEmpty()) {
                                result.error("INVALID_ARGS", "Device address is required", null)
                                return@setMethodCallHandler
                            }

                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                                result.error("UNSUPPORTED", "L2CAP requires Android 10+ (API 29)", null)
                                return@setMethodCallHandler
                            }

                            startBleL2capSync(deviceAddress, fileId, psm, result)
                        }

                        "connectWifiSoftAp" -> {
                            val ssidPattern = call.argument<String>("ssidPattern") ?: "XIAO-Audio-Hotspot"
                            val passphrase = call.argument<String>("passphrase") ?: "xiaoesp32c3"

                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                                result.error("UNSUPPORTED", "WifiNetworkSpecifier requires Android 10+", null)
                                return@setMethodCallHandler
                            }

                            activityScope.launch(Dispatchers.IO) {
                                val wifiManager = iotWifiManager ?: IotWifiManager(applicationContext)
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
                                iotWifiManager?.disconnect()
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("WIFI_DISCONNECT_FAILED", e.message, null)
                            }
                        }

                        "isWifiConnected" -> {
                            result.success(iotWifiManager?.isConnected() == true)
                        }

                        "startWifiSoftApSync" -> {
                            val ssidPattern = call.argument<String>("ssidPattern") ?: "XIAO-Audio-Hotspot"
                            val passphrase = call.argument<String>("passphrase") ?: "xiaoesp32c3"
                            val fileId = call.argument<Number>("fileId")?.toLong() ?: 0L
                            val startOffset = call.argument<Number>("startOffset")?.toLong() ?: 0L
                            val keepConnected = call.argument<Boolean>("keepConnected") ?: false

                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                                result.error("UNSUPPORTED", "WifiNetworkSpecifier requires Android 10+", null)
                                return@setMethodCallHandler
                            }

                            startWifiSoftApSync(ssidPattern, passphrase, fileId, startOffset, keepConnected, result)
                        }

                        "cancelSync" -> {
                            activeSyncJob?.cancel()
                            try { iotWifiManager?.disconnect() } catch (_: Throwable) {}
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
        result: MethodChannel.Result
    ) {
        activeSyncJob?.cancel()
        activeSyncJob = activityScope.launch(Dispatchers.IO) {
            try {
                sendEvent("connecting", 0.0, 0, 0, "Opening L2CAP channel (PSM 0x${psm.toString(16)})...")

                val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                val adapter = btManager?.adapter ?: throw IOException("Bluetooth Adapter unavailable")
                val device = adapter.getRemoteDevice(deviceAddress)
                val targetFile = File(filesDir, "clip_${fileId}.wav")
                val receiver = BleL2capAudioReceiver(applicationContext)

                val startTime = System.currentTimeMillis()

                val success = receiver.receiveAudioViaL2cap(
                    device = device,
                    psm = psm,
                    outputFile = targetFile
                ) { bytesReceived, totalBytes ->
                    val elapsedSec = (System.currentTimeMillis() - startTime) / 1000.0
                    val speedKb = if (elapsedSec > 0) (bytesReceived / 1024.0) / elapsedSec else 0.0
                    val progress = if (totalBytes > 0) (bytesReceived.toDouble() / totalBytes.toDouble()).coerceIn(0.0, 1.0) else 0.0

                    sendEvent(
                        status = "transferring",
                        progress = progress,
                        bytesReceived = bytesReceived,
                        totalBytes = totalBytes,
                        message = "${String.format("%.1f", speedKb)} KB/s (BLE L2CAP)",
                        filePath = targetFile.absolutePath
                    )
                }

                withContext(Dispatchers.Main) {
                    if (success) {
                        sendEvent("completed", 1.0, targetFile.length(), targetFile.length(), "Sync complete", targetFile.absolutePath)
                        result.success(targetFile.absolutePath)
                    } else {
                        sendEvent("failed", 0.0, 0, 0, "L2CAP sync failed or CRC mismatch")
                        result.error("SYNC_FAILED", "L2CAP audio transfer failed", null)
                    }
                }
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
        keepConnected: Boolean,
        result: MethodChannel.Result
    ) {
        activeSyncJob?.cancel()
        activeSyncJob = activityScope.launch(Dispatchers.IO) {
            val wifiManager = iotWifiManager ?: IotWifiManager(applicationContext)
            try {
                val activeNet = wifiManager.getActiveNetwork()
                val network: Network = if (wifiManager.isConnected() && activeNet != null) {
                    Log.i(TAG, "Reusing already active IoT Wi-Fi connection: $activeNet")
                    activeNet
                } else {
                    sendEvent("connecting", 0.0, 0, 0, "Connecting to XIAO-Audio-Hotspot...")
                    wifiManager.connect(ssidPattern, passphrase)
                }

                val client = IotHttpClientFactory.createClient(network)

                sendEvent("connected", 0.05, 0, 0, "SoftAP connected! Downloading audio...")

                val url = if (fileId > 0) "http://192.168.4.1/api/download?id=$fileId" else "http://192.168.4.1/api/download"
                
                val reqBuilder = Request.Builder().url(url)
                if (startOffset > 0) {
                    reqBuilder.addHeader("Range", "bytes=$startOffset-")
                }

                val response = client.newCall(reqBuilder.build()).execute()
                if (!response.isSuccessful && response.code != 206) {
                    throw IOException("Server returned HTTP ${response.code}")
                }

                val body = response.body ?: throw IOException("Empty response body")
                val totalLength = (response.header("Content-Length")?.toLongOrNull() ?: 0L) + startOffset
                val targetFile = File(filesDir, if (fileId > 0) "clip_${fileId}.wav" else "clip_latest.wav")
                val tempFile = File(filesDir, "${targetFile.name}.part")

                var bytesReadTotal = if (startOffset > 0 && tempFile.exists()) tempFile.length() else 0L
                val fos = FileOutputStream(tempFile, startOffset > 0)
                val buffer = ByteArray(16384)
                val startTime = System.currentTimeMillis()

                body.byteStream().use { input ->
                    fos.use { output ->
                        var read: Int
                        while (input.read(buffer).also { read = it } != -1) {
                            output.write(buffer, 0, read)
                            bytesReadTotal += read

                            val elapsedSec = (System.currentTimeMillis() - startTime) / 1000.0
                            val speedMb = if (elapsedSec > 0) ((bytesReadTotal - startOffset) / (1024.0 * 1024.0)) / elapsedSec else 0.0
                            val progress = if (totalLength > 0) (bytesReadTotal.toDouble() / totalLength.toDouble()).coerceIn(0.0, 1.0) else 0.5

                            sendEvent(
                                status = "transferring",
                                progress = progress,
                                bytesReceived = bytesReadTotal,
                                totalBytes = totalLength,
                                message = "${String.format("%.2f", speedMb)} MB/s (Wi-Fi Turbo)",
                                filePath = targetFile.absolutePath
                            )
                        }
                    }
                }

                if (!keepConnected) {
                    try { wifiManager.disconnect() } catch (_: Throwable) {}
                }

                if (targetFile.exists()) targetFile.delete()
                tempFile.renameTo(targetFile)

                withContext(Dispatchers.Main) {
                    sendEvent("completed", 1.0, targetFile.length(), targetFile.length(), "Sync complete", targetFile.absolutePath)
                    result.success(targetFile.absolutePath)
                }
            } catch (e: Exception) {
                if (!keepConnected) {
                    try { iotWifiManager?.disconnect() } catch (_: Throwable) {}
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
        super.onDestroy()
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}
