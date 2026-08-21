package com.sphaerox.companion_app.ble

import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.io.InputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.zip.CRC32

class BleL2capAudioReceiver(private val context: Context) {

    private var l2capSocket: BluetoothSocket? = null

    @RequiresApi(Build.VERSION_CODES.Q)
    suspend fun receiveAudioViaL2cap(
        device: BluetoothDevice,
        psm: Int = 0x0081,
        outputFile: File,
        onProgress: (bytesReceived: Long, totalBytes: Long) -> Unit
    ): Boolean = withContext(Dispatchers.IO) {
        var fileOutputStream: FileOutputStream? = null
        val tempFile = File(outputFile.parentFile, "${outputFile.name}.part")
        try {
            Log.i(TAG, "Opening L2CAP Channel to PSM: 0x${psm.toString(16)} on device: ${device.address}")
            l2capSocket = device.createInsecureL2capChannel(psm)
            l2capSocket?.connect()

            val inputStream: InputStream = l2capSocket?.inputStream 
                ?: throw IOException("Failed to obtain L2CAP socket input stream")
            
            // Support resume appending on partial transfers
            var initialBytes = 0L
            val fileCrc = CRC32()
            if (tempFile.exists()) {
                initialBytes = tempFile.length()
                // Recompute CRC32 of existing partial bytes
                FileInputStream(tempFile).use { fis ->
                    val buffer = ByteArray(4096)
                    var read: Int
                    while (fis.read(buffer).also { read = it } != -1) {
                        fileCrc.update(buffer, 0, read)
                    }
                }
                Log.i(TAG, "Resuming partial transfer from byte offset: $initialBytes")
            }

            fileOutputStream = FileOutputStream(tempFile, true)
            var totalBytesExpected = 0L
            var totalBytesReceived = initialBytes

            // EXACT 32-Byte SyncChunkHeader allocation
            val headerBuffer = ByteBuffer.allocate(32).order(ByteOrder.LITTLE_ENDIAN)

            while (l2capSocket?.isConnected == true) {
                // 1. Read exactly 32 bytes for SyncChunkHeader
                var headerBytesRead = 0
                headerBuffer.clear()
                while (headerBytesRead < 32) {
                    val read = inputStream.read(headerBuffer.array(), headerBytesRead, 32 - headerBytesRead)
                    if (read == -1) break
                    headerBytesRead += read
                }
                if (headerBytesRead == 0) break // Clean EOF from peripheral
                if (headerBytesRead < 32) {
                    throw IOException("Incomplete header received ($headerBytesRead/32 bytes)")
                }

                headerBuffer.position(0)
                val magic = headerBuffer.short.toInt() and 0xFFFF
                if (magic != 0xAA55) {
                    throw IOException("Invalid magic in chunk header: 0x${magic.toString(16)}")
                }

                val version = headerBuffer.get()
                val frameType = headerBuffer.get()
                val fileId = headerBuffer.int
                val seqNum = headerBuffer.int
                val byteOffset = headerBuffer.int
                val payloadLen = headerBuffer.short.toInt() and 0xFFFF
                val reserved = headerBuffer.short
                val totalFileSize = headerBuffer.int.toLong() and 0xFFFFFFFFL
                val chunkCrc32 = headerBuffer.int.toLong() and 0xFFFFFFFFL
                val expectedFileCrc32 = headerBuffer.int.toLong() and 0xFFFFFFFFL

                totalBytesExpected = totalFileSize

                if (frameType == 0x05.toByte()) { // FIN frame
                    Log.i(TAG, "Received L2CAP FIN frame from peripheral (File ID: $fileId)")
                    break
                }

                // 2. Read exactly payloadLen binary audio bytes
                var payloadBytesRead = 0
                val payload = ByteArray(payloadLen)
                while (payloadBytesRead < payloadLen) {
                    val read = inputStream.read(payload, payloadBytesRead, payloadLen - payloadBytesRead)
                    if (read == -1) {
                        throw IOException("Premature EOF during payload read ($payloadBytesRead/$payloadLen bytes)")
                    }
                    payloadBytesRead += read
                }

                // 3. Verify chunk CRC32 - Discard corrupted chunks
                val chunkCrc = CRC32()
                chunkCrc.update(payload, 0, payloadBytesRead)
                if (chunkCrc.value != chunkCrc32) {
                    throw IOException("Chunk CRC32 mismatch on seq $seqNum (calc=0x${chunkCrc.value.toString(16)}, exp=0x${chunkCrc32.toString(16)})")
                }

                // 4. Write valid chunk to disk and update running file CRC
                fileOutputStream.write(payload, 0, payloadBytesRead)
                fileCrc.update(payload, 0, payloadBytesRead)
                totalBytesReceived += payloadBytesRead

                onProgress(totalBytesReceived, totalBytesExpected)

                if (totalBytesReceived >= totalBytesExpected) {
                    Log.i(TAG, "All bytes received ($totalBytesReceived/$totalBytesExpected). Validating file CRC32...")
                    if (fileCrc.value != expectedFileCrc32) {
                        throw IOException("File CRC32 verification failed (calc=0x${fileCrc.value.toString(16)}, exp=0x${expectedFileCrc32.toString(16)})")
                    }
                    Log.i(TAG, "File CRC32 (0x${fileCrc.value.toString(16)}) verified successfully!")
                    break
                }
            }

            fileOutputStream.flush()
            fileOutputStream.close()
            fileOutputStream = null

            // 5. Atomic rename from .part to final destination file
            if (outputFile.exists()) outputFile.delete()
            if (!tempFile.renameTo(outputFile)) {
                throw IOException("Failed to rename temporary file to destination: ${outputFile.absolutePath}")
            }

            Log.i(TAG, "Audio sync completed successfully: ${outputFile.absolutePath} (${outputFile.length()} bytes)")
            return@withContext true
        } catch (e: Exception) {
            Log.e(TAG, "L2CAP Sync Exception: ${e.message}", e)
            return@withContext false
        } finally {
            try { fileOutputStream?.close() } catch (_: Exception) {}
            try { l2capSocket?.close() } catch (_: Exception) {}
            l2capSocket = null
        }
    }

    companion object {
        private const val TAG = "BleL2capAudioReceiver"
    }
}
