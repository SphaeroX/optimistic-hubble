package com.sphaerox.companion_app.network

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PatternMatcher
import android.util.Log
import androidx.annotation.RequiresApi
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import java.util.concurrent.atomic.AtomicBoolean

sealed class WifiConnectionState {
    object Idle : WifiConnectionState()
    object Connecting : WifiConnectionState()
    data class Connected(val network: Network) : WifiConnectionState()
    data class Failed(val reason: String) : WifiConnectionState()
    object Disconnected : WifiConnectionState()
}

class IotWifiManager(private val context: Context) {

    private val connectivityManager =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    private var activeCallback: ConnectivityManager.NetworkCallback? = null
    private val isConnecting = AtomicBoolean(false)

    @RequiresApi(Build.VERSION_CODES.Q)
    fun connectToEsp32SoftAp(
        ssidPattern: String = "XIAO-Audio-Hotspot",
        passphrase: String = "xiaoesp32c3",
        timeoutMs: Int = 30000
    ): Flow<WifiConnectionState> = callbackFlow {
        // Disconnect any lingering previous callback first to avoid duplicate dialogs
        disconnect()

        if (!isConnecting.compareAndSet(false, true)) {
            trySend(WifiConnectionState.Failed("Connection already in progress"))
            close()
            return@callbackFlow
        }

        trySend(WifiConnectionState.Connecting)

        val cleanSsid = if (ssidPattern.contains(".*")) "XIAO-Audio-Hotspot" else ssidPattern

        val specifierBuilder = WifiNetworkSpecifier.Builder()
        if (cleanSsid.contains("*")) {
            specifierBuilder.setSsidPattern(PatternMatcher(cleanSsid, PatternMatcher.PATTERN_SIMPLE_GLOB))
        } else {
            specifierBuilder.setSsid(cleanSsid)
        }
        specifierBuilder.setWpa2Passphrase(passphrase)
        val specifier = specifierBuilder.build()

        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Log.i(TAG, "IoT Wi-Fi Connected: $network -> Binding process to network")
                isConnecting.set(false)
                try {
                    connectivityManager.bindProcessToNetwork(network)
                } catch (e: Exception) {
                    Log.w(TAG, "Could not bind process to network: ${e.message}")
                }
                trySend(WifiConnectionState.Connected(network))
            }

            override fun onLost(network: Network) {
                Log.w(TAG, "IoT Wi-Fi Lost: $network")
                isConnecting.set(false)
                try {
                    connectivityManager.bindProcessToNetwork(null)
                } catch (_: Exception) {}
                trySend(WifiConnectionState.Disconnected)
            }

            override fun onUnavailable() {
                Log.e(TAG, "IoT Wi-Fi Unavailable (Timeout or User Dismissed)")
                isConnecting.set(false)
                try {
                    connectivityManager.bindProcessToNetwork(null)
                } catch (_: Exception) {}
                trySend(WifiConnectionState.Failed("User cancelled or device not found"))
            }
        }

        activeCallback = callback
        val handler = Handler(Looper.getMainLooper())
        try {
            connectivityManager.requestNetwork(request, callback, handler, timeoutMs)
        } catch (e: Exception) {
            isConnecting.set(false)
            trySend(WifiConnectionState.Failed(e.message ?: "Failed to request network"))
        }

        awaitClose {
            disconnect()
        }
    }

    fun disconnect() {
        activeCallback?.let { callback ->
            try {
                connectivityManager.bindProcessToNetwork(null)
                connectivityManager.unregisterNetworkCallback(callback)
                Log.i(TAG, "IoT Wi-Fi unregistered. Normal routing restored.")
            } catch (e: Exception) {
                Log.w(TAG, "Error unregistering network callback: ${e.message}")
            }
        }
        activeCallback = null
        isConnecting.set(false)
    }

    companion object {
        private const val TAG = "IotWifiManager"
    }
}
