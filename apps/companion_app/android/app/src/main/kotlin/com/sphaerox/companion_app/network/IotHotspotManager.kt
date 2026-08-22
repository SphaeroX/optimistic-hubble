package com.sphaerox.companion_app.network

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeout
import java.io.IOException
import java.net.Inet4Address
import java.net.NetworkInterface

data class HotspotCredentials(
    val ssid: String,
    val passphrase: String,
    val ip: String,
    val port: Int = 8080
)

class IotHotspotManager(private val context: Context) {

    private val wifiManager =
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

    @Volatile
    private var activeReservation: WifiManager.LocalOnlyHotspotReservation? = null

    private val stateLock = Any()

    fun isHotspotActive(): Boolean {
        synchronized(stateLock) {
            return activeReservation != null
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    suspend fun startHotspot(port: Int = 8080, timeoutMs: Long = 20000): HotspotCredentials {
        synchronized(stateLock) {
            val existing = activeReservation
            if (existing != null) {
                Log.i(TAG, "Reusing existing LocalOnlyHotspot reservation")
                return extractCredentials(existing, port)
            }
        }

        val deferred = CompletableDeferred<HotspotCredentials>()
        val mainHandler = Handler(Looper.getMainLooper())

        val callback = object : WifiManager.LocalOnlyHotspotCallback() {
            override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation?) {
                super.onStarted(reservation)
                Log.i(TAG, "LocalOnlyHotspot onStarted callback received")
                if (reservation == null) {
                    deferred.completeExceptionally(IOException("Reservation is null"))
                    return
                }

                synchronized(stateLock) {
                    activeReservation = reservation
                }

                try {
                    val creds = extractCredentials(reservation, port)
                    Log.i(TAG, "Hotspot started successfully: SSID=${creds.ssid}, IP=${creds.ip}, Port=${creds.port}")
                    deferred.complete(creds)
                } catch (e: Exception) {
                    Log.e(TAG, "Error extracting hotspot credentials: ${e.message}", e)
                    deferred.completeExceptionally(e)
                }
            }

            override fun onStopped() {
                super.onStopped()
                Log.i(TAG, "LocalOnlyHotspot onStopped callback received")
                synchronized(stateLock) {
                    activeReservation = null
                }
            }

            override fun onFailed(reason: Int) {
                super.onFailed(reason)
                val reasonMsg = when (reason) {
                    ERROR_NO_CHANNEL -> "ERROR_NO_CHANNEL"
                    ERROR_GENERIC -> "ERROR_GENERIC"
                    ERROR_INCOMPATIBLE_MODE -> "ERROR_INCOMPATIBLE_MODE"
                    ERROR_TETHERING_DISALLOWED -> "ERROR_TETHERING_DISALLOWED"
                    else -> "Reason code $reason"
                }
                Log.e(TAG, "LocalOnlyHotspot onFailed: $reasonMsg")
                synchronized(stateLock) {
                    activeReservation = null
                }
                deferred.completeExceptionally(IOException("Failed to start Local-Only Hotspot: $reasonMsg"))
            }
        }

        try {
            wifiManager.startLocalOnlyHotspot(callback, mainHandler)
        } catch (e: Exception) {
            Log.e(TAG, "Exception calling startLocalOnlyHotspot: ${e.message}", e)
            throw IOException("Error launching LocalOnlyHotspot: ${e.message}", e)
        }

        return try {
            withTimeout(timeoutMs) {
                deferred.await()
            }
        } catch (e: Exception) {
            stopHotspot()
            throw e
        }
    }

    fun stopHotspot() {
        synchronized(stateLock) {
            val reservation = activeReservation
            activeReservation = null
            if (reservation != null) {
                try {
                    reservation.close()
                    Log.i(TAG, "LocalOnlyHotspot reservation closed.")
                } catch (e: Exception) {
                    Log.w(TAG, "Error closing hotspot reservation: ${e.message}")
                }
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun extractCredentials(
        reservation: WifiManager.LocalOnlyHotspotReservation,
        port: Int
    ): HotspotCredentials {
        var rawSsid = ""
        var rawPass = ""

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val softApConfig = reservation.softApConfiguration
            if (softApConfig != null) {
                rawSsid = softApConfig.ssid ?: ""
                rawPass = softApConfig.passphrase ?: ""
            }
        }

        if (rawSsid.isEmpty() && Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            @Suppress("DEPRECATION")
            val wifiConfig = reservation.wifiConfiguration
            if (wifiConfig != null) {
                rawSsid = wifiConfig.SSID ?: ""
                rawPass = wifiConfig.preSharedKey ?: ""
            }
        }

        // Clean any surrounding quotes commonly added by Android
        val cleanSsid = rawSsid.removeSurrounding("\"")
        val cleanPass = rawPass.removeSurrounding("\"")

        val hostIp = getLocalIpAddress()

        return HotspotCredentials(
            ssid = cleanSsid,
            passphrase = cleanPass,
            ip = hostIp,
            port = port
        )
    }

    private fun getLocalIpAddress(): String {
        var apIp: String? = null
        var tetherIp: String? = null
        val fallbackIp = "192.168.43.1"

        try {
            val interfaces = NetworkInterface.getNetworkInterfaces() ?: return fallbackIp
            while (interfaces.hasMoreElements()) {
                val iface = interfaces.nextElement()
                if (!iface.isUp || iface.isLoopback) continue

                val name = iface.name.lowercase()
                val addresses = iface.inetAddresses

                while (addresses.hasMoreElements()) {
                    val addr = addresses.nextElement()
                    if (!addr.isLoopbackAddress && addr is Inet4Address) {
                        val hostAddr = addr.hostAddress ?: continue

                        // Specific Hotspot AP / Tethering interfaces on Android (e.g. ap0, swlan0, softap0, wlan1, tether, p2p)
                        if (name.startsWith("ap") || name.startsWith("swlan") || name.startsWith("softap") || name.contains("tether")) {
                            apIp = hostAddr
                        } else if (hostAddr.startsWith("192.168.43.") || hostAddr.startsWith("192.168.49.") || hostAddr.startsWith("192.168.50.")) {
                            tetherIp = hostAddr
                        } else if (apIp == null && tetherIp == null && (name.contains("wlan1") || name.contains("p2p"))) {
                            tetherIp = hostAddr
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error determining local IP address: ${e.message}")
        }

        return apIp ?: tetherIp ?: fallbackIp
    }

    companion object {
        private const val TAG = "IotHotspotManager"
    }
}
