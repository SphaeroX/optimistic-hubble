package com.sphaerox.companion_app.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.sphaerox.companion_app.ble.BleL2capAudioReceiver
import com.sphaerox.companion_app.network.IotHttpClientFactory
import com.sphaerox.companion_app.network.IotWifiManager
import com.sphaerox.companion_app.network.WifiConnectionState
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

class AudioSyncForegroundService : Service() {

    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private lateinit var notificationManager: NotificationManager

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val deviceAddress = intent?.getStringExtra(EXTRA_DEVICE_ADDRESS)
        val syncTier = intent?.getIntExtra(EXTRA_SYNC_TIER, TIER_BLE_L2CAP) ?: TIER_BLE_L2CAP
        val fileId = intent?.getLongExtra(EXTRA_FILE_ID, System.currentTimeMillis()) ?: System.currentTimeMillis()

        val initialNotification = buildProgressNotification("Connecting to XIAO ESP32-C3...", 0, 100)

        // Android 14 (API 34) & Android 15 (API 35+) Foreground Service Type Compliance
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                initialNotification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            startForeground(NOTIFICATION_ID, initialNotification)
        }

        if (deviceAddress.isNullOrEmpty() && syncTier == TIER_BLE_L2CAP) {
            Log.e(TAG, "No Bluetooth device address provided for Tier 1 sync. Stopping service.")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }

        serviceScope.launch {
            try {
                val targetFile = File(filesDir, "clip_${fileId}.wav")
                var syncSuccess = false

                if (syncTier == TIER_BLE_L2CAP && deviceAddress != null) {
                    // Tier 1: Silent BLE L2CAP CoC Transfer (< 2.0 MB)
                    Log.i(TAG, "Executing Tier 1 BLE L2CAP sync for device: $deviceAddress")
                    val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                    val device = btManager.adapter.getRemoteDevice(deviceAddress)
                    val receiver = BleL2capAudioReceiver(applicationContext)

                    syncSuccess = receiver.receiveAudioViaL2cap(
                        device = device,
                        psm = 0x0081,
                        outputFile = targetFile
                    ) { bytesReceived, totalBytes ->
                        val percent = if (totalBytes > 0) ((bytesReceived * 100) / totalBytes).toInt() else 0
                        notificationManager.notify(
                            NOTIFICATION_ID,
                            buildProgressNotification("Syncing BLE audio: $percent% (${bytesReceived / 1024} KB)", percent, 100)
                        )
                    }
                } else {
                    // Tier 2: Dynamic Wi-Fi SoftAP Transfer (>= 2.0 MB)
                    Log.i(TAG, "Executing Tier 2 Wi-Fi SoftAP sync for file ID: $fileId")
                    val wifiManager = IotWifiManager(applicationContext)
                    val connectionState = wifiManager.connectToEsp32SoftAp().first { it is WifiConnectionState.Connected || it is WifiConnectionState.Failed }

                    if (connectionState is WifiConnectionState.Connected) {
                        val client = IotHttpClientFactory.createClient(connectionState.network)
                        val request = Request.Builder()
                            .url("http://192.168.4.1/api/download?id=$fileId")
                            .build()

                        val response = client.newCall(request).execute()
                        if (response.isSuccessful) {
                            val body = response.body ?: throw IOException("Empty response body from ESP32 SoftAP")
                            val totalBytes = body.contentLength()
                            var bytesReadTotal = 0L
                            val buffer = ByteArray(8192)

                            FileOutputStream(targetFile).use { fos ->
                                body.byteStream().use { input ->
                                    var read: Int
                                    while (input.read(buffer).also { read = it } != -1) {
                                        fos.write(buffer, 0, read)
                                        bytesReadTotal += read
                                        val percent = if (totalBytes > 0) ((bytesReadTotal * 100) / totalBytes).toInt() else 0
                                        notificationManager.notify(
                                            NOTIFICATION_ID,
                                            buildProgressNotification("Downloading Wi-Fi audio: $percent%", percent, 100)
                                        )
                                    }
                                }
                            }
                            syncSuccess = true
                        }
                        wifiManager.disconnect()
                    }
                }

                if (syncSuccess) {
                    Log.i(TAG, "Audio synchronization succeeded: ${targetFile.absolutePath}")
                    notificationManager.notify(
                        NOTIFICATION_ID,
                        buildProgressNotification("Sync Complete! Ready for transcription.", 100, 100)
                    )
                } else {
                    Log.e(TAG, "Audio synchronization failed.")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Fatal error during audio sync execution: ${e.message}", e)
            } finally {
                delay(1000)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }

        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Audio Sync Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows ongoing transfer progress with XIAO recorder"
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildProgressNotification(content: String, progress: Int, max: Int): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("XIAO Voice Sync")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setProgress(max, progress, progress == 0)
            .setOngoing(progress < max)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
    }

    companion object {
        private const val TAG = "AudioSyncFGService"
        private const val CHANNEL_ID = "channel_audio_sync"
        private const val NOTIFICATION_ID = 2001
        const val EXTRA_DEVICE_ADDRESS = "extra_device_address"
        const val EXTRA_SYNC_TIER = "extra_sync_tier"
        const val EXTRA_FILE_ID = "extra_file_id"
        const val TIER_BLE_L2CAP = 1
        const val TIER_WIFI_SOFTAP = 2

        fun start(context: Context, deviceAddress: String, tier: Int = TIER_BLE_L2CAP, fileId: Long = 0L) {
            val intent = Intent(context, AudioSyncForegroundService::class.java).apply {
                putExtra(EXTRA_DEVICE_ADDRESS, deviceAddress)
                putExtra(EXTRA_SYNC_TIER, tier)
                putExtra(EXTRA_FILE_ID, fileId)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}
