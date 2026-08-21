package com.sphaerox.companion_app.worker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.work.*
import com.sphaerox.companion_app.ble.BleL2capAudioReceiver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

class AudioSyncWorker(
    private val appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val deviceAddress = inputData.getString(KEY_DEVICE_ADDRESS)
        if (deviceAddress.isNullOrEmpty()) {
            Log.e(TAG, "Worker failed: No device address supplied")
            return@withContext Result.failure()
        }

        try {
            // Android 14/15 compliance: WorkManager binds directly to connectedDevice FGS
            setForeground(createForegroundInfo("Starting background sync...", 0))

            val btManager = appContext.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            val device = btManager.adapter.getRemoteDevice(deviceAddress)
            val targetFile = File(appContext.filesDir, "audio_worker_${System.currentTimeMillis()}.wav")
            val receiver = BleL2capAudioReceiver(appContext)

            val success = receiver.receiveAudioViaL2cap(
                device = device,
                psm = 0x0081,
                outputFile = targetFile
            ) { bytesReceived, totalBytes ->
                val percent = if (totalBytes > 0) ((bytesReceived * 100) / totalBytes).toInt() else 0
                setProgressAsync(workDataOf(KEY_PROGRESS to percent))
            }

            if (success) {
                Log.i(TAG, "AudioSyncWorker successfully synced: ${targetFile.absolutePath}")
                Result.success(workDataOf(KEY_OUTPUT_PATH to targetFile.absolutePath))
            } else {
                if (runAttemptCount < 3) Result.retry() else Result.failure()
            }
        } catch (e: Exception) {
            Log.e(TAG, "AudioSyncWorker exception: ${e.message}", e)
            if (runAttemptCount < 3) Result.retry() else Result.failure()
        }
    }

    private fun createForegroundInfo(content: String, progress: Int): ForegroundInfo {
        createNotificationChannel()
        val notification: Notification = NotificationCompat.Builder(appContext, CHANNEL_ID)
            .setContentTitle("XIAO Background Audio Sync")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setProgress(100, progress, progress == 0)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ForegroundInfo(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE
            )
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Background Audio Sync",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    companion object {
        private const val TAG = "AudioSyncWorker"
        private const val CHANNEL_ID = "channel_audio_worker_sync"
        private const val NOTIFICATION_ID = 2002
        const val KEY_DEVICE_ADDRESS = "key_device_address"
        const val KEY_PROGRESS = "key_progress"
        const val KEY_OUTPUT_PATH = "key_output_path"

        fun enqueueExpeditedSync(context: Context, deviceAddress: String) {
            val data = workDataOf(KEY_DEVICE_ADDRESS to deviceAddress)
            val request = OneTimeWorkRequestBuilder<AudioSyncWorker>()
                .setInputData(data)
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .setConstraints(
                    Constraints.Builder()
                        .setRequiredNetworkType(NetworkType.NOT_REQUIRED)
                        .build()
                )
                .build()

            WorkManager.getInstance(context).enqueue(request)
        }
    }
}
