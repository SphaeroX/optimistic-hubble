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
        ssidPattern: String = "XIAO-Audio-.*",
        passphrase: String = "xiaoesp32c3",
        timeoutMs: Int = 25000
    ): Flow<WifiConnectionState> = callbackFlow {
        if (!isConnecting.compareAndSet(false, true)) {
            trySend(WifiConnectionState.Failed("Connection already in progress"))
            close()
            return@callbackFlow
        }

        trySend(WifiConnectionState.Connecting)

        val specifier = WifiNetworkSpecifier.Builder()
            .setSsidPattern(PatternMatcher(ssidPattern, PatternMatcher.PATTERN_SIMPLE_GLOB))
            .setWpa2Passphrase(passphrase)
            .build()

        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            // MANDATORY: Remove Internet requirement for local SoftAP
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                Log.i(TAG, "IoT Wi-Fi Connected: $network")
                isConnecting.set(false)
                trySend(WifiConnectionState.Connected(network))
            }

            override fun onLost(network: Network) {
                Log.w(TAG, "IoT Wi-Fi Lost: $network")
                isConnecting.set(false)
                trySend(WifiConnectionState.Disconnected)
            }

            override fun onUnavailable() {
                Log.e(TAG, "IoT Wi-Fi Unavailable (Timeout or User Dismissed)")
                isConnecting.set(false)
                trySend(WifiConnectionState.Failed("User cancelled or device not found"))
            }
        }

        activeCallback = callback
        val handler = Handler(Looper.getMainLooper())
        connectivityManager.requestNetwork(request, callback, handler, timeoutMs)

        awaitClose {
            disconnect()
        }
    }

    fun disconnect() {
        activeCallback?.let { callback ->
            try {
                connectivityManager.unregisterNetworkCallback(callback)
                Log.i(TAG, "IoT Wi-Fi unregistered. Default cellular network active.")
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
