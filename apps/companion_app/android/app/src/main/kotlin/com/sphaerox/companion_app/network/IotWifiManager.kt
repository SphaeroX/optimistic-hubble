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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import java.io.IOException

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

    @Volatile
    private var activeCallback: ConnectivityManager.NetworkCallback? = null

    @Volatile
    private var activeNetwork: Network? = null

    private var connectionDeferred: CompletableDeferred<Network>? = null
    private val stateLock = Any()

    fun isConnected(): Boolean {
        synchronized(stateLock) {
            return activeNetwork != null && activeCallback != null
        }
    }

    fun getActiveNetwork(): Network? {
        synchronized(stateLock) {
            return activeNetwork
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    suspend fun connect(
        ssidPattern: String = "XIAO-Audio-Hotspot",
        passphrase: String = "xiaoesp32c3",
        timeoutMs: Int = 30000
    ): Network {
        val deferred: CompletableDeferred<Network>
        synchronized(stateLock) {
            val existing = activeNetwork
            if (existing != null && activeCallback != null) {
                Log.i(TAG, "Reusing existing active SoftAP connection: $existing")
                return existing
            }

            val inFlight = connectionDeferred
            if (inFlight != null && !inFlight.isCompleted) {
                Log.i(TAG, "Reusing in-flight SoftAP connection request")
                deferred = inFlight
            } else {
                val newDeferred = CompletableDeferred<Network>()
                connectionDeferred = newDeferred
                deferred = newDeferred

                val cleanPattern = ssidPattern.replace(".*", "*")

                val specifierBuilder = WifiNetworkSpecifier.Builder()
                if (cleanPattern.contains("*")) {
                    specifierBuilder.setSsidPattern(PatternMatcher(cleanPattern, PatternMatcher.PATTERN_SIMPLE_GLOB))
                } else {
                    specifierBuilder.setSsid(cleanPattern)
                }

                if (passphrase.isNotBlank() && passphrase.length >= 8) {
                    specifierBuilder.setWpa2Passphrase(passphrase)
                }
                val specifier = specifierBuilder.build()

                val request = NetworkRequest.Builder()
                    .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
                    .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                    .setNetworkSpecifier(specifier)
                    .build()

                val callback = object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        Log.i(TAG, "IoT Wi-Fi Connected: $network -> Binding process to network")
                        synchronized(stateLock) {
                            if (deferred.isCompleted || activeCallback != this) {
                                Log.w(TAG, "IoT Wi-Fi connected after disconnect/cancellation; unbinding immediately.")
                                try {
                                    connectivityManager.bindProcessToNetwork(null)
                                } catch (_: Exception) {}
                                try {
                                    connectivityManager.unregisterNetworkCallback(this)
                                } catch (_: Exception) {}
                                return
                            }
                            activeNetwork = network
                            activeCallback = this
                            connectionDeferred = null
                            try {
                                connectivityManager.bindProcessToNetwork(network)
                            } catch (e: Exception) {
                                Log.w(TAG, "Could not bind process to network: ${e.message}")
                            }
                            deferred.complete(network)
                        }
                    }

                    override fun onLost(network: Network) {
                        Log.w(TAG, "IoT Wi-Fi Lost: $network")
                        synchronized(stateLock) {
                            val wasActive = (activeNetwork == network || activeCallback == this)
                            if (wasActive) {
                                activeNetwork = null
                                activeCallback = null
                                connectionDeferred = null
                                try {
                                    connectivityManager.bindProcessToNetwork(null)
                                } catch (_: Exception) {}
                            }
                            try {
                                connectivityManager.unregisterNetworkCallback(this)
                            } catch (_: Exception) {}
                            if (!deferred.isCompleted) {
                                deferred.completeExceptionally(IOException("Wi-Fi network lost"))
                            }
                        }
                    }

                    override fun onUnavailable() {
                        Log.e(TAG, "IoT Wi-Fi Unavailable (Timeout or User Dismissed)")
                        synchronized(stateLock) {
                            if (activeCallback == this) {
                                activeNetwork = null
                                activeCallback = null
                                connectionDeferred = null
                                try {
                                    connectivityManager.bindProcessToNetwork(null)
                                } catch (_: Exception) {}
                            }
                            try {
                                connectivityManager.unregisterNetworkCallback(this)
                            } catch (_: Exception) {}
                            if (!deferred.isCompleted) {
                                deferred.completeExceptionally(IOException("User cancelled or device not found"))
                            }
                        }
                    }
                }

                activeCallback = callback
                val handler = Handler(Looper.getMainLooper())
                try {
                    connectivityManager.requestNetwork(request, callback, handler, timeoutMs)
                } catch (e: Exception) {
                    synchronized(stateLock) {
                        activeCallback = null
                        connectionDeferred = null
                    }
                    deferred.completeExceptionally(e)
                }
            }
        }

        return try {
            deferred.await()
        } catch (e: CancellationException) {
            disconnect()
            throw e
        }
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    fun connectToEsp32SoftAp(
        ssidPattern: String = "XIAO-Audio-Hotspot",
        passphrase: String = "xiaoesp32c3",
        timeoutMs: Int = 30000
    ): Flow<WifiConnectionState> = callbackFlow {
        val existing = activeNetwork
        if (existing != null && activeCallback != null) {
            trySend(WifiConnectionState.Connected(existing))
            awaitClose {
                // Keep callback active; explicit disconnect() required
            }
            return@callbackFlow
        }

        trySend(WifiConnectionState.Connecting)
        try {
            val network = connect(ssidPattern, passphrase, timeoutMs)
            trySend(WifiConnectionState.Connected(network))
        } catch (e: Exception) {
            trySend(WifiConnectionState.Failed(e.message ?: "Connection failed"))
        }

        awaitClose {
            // Do NOT unregister callback on flow closure to prevent tearing down
            // the active network connection between successive transfers.
        }
    }

    fun disconnect() {
        synchronized(stateLock) {
            val callback = activeCallback
            activeCallback = null
            activeNetwork = null

            val inFlight = connectionDeferred
            connectionDeferred = null
            if (inFlight != null && !inFlight.isCompleted) {
                inFlight.completeExceptionally(IOException("Connection aborted by disconnect"))
            }

            try {
                connectivityManager.bindProcessToNetwork(null)
            } catch (e: Exception) {
                Log.w(TAG, "Error unbinding process network: ${e.message}")
            }

            if (callback != null) {
                try {
                    connectivityManager.unregisterNetworkCallback(callback)
                    Log.i(TAG, "IoT Wi-Fi unregistered. Normal routing restored.")
                } catch (e: Exception) {
                    Log.w(TAG, "Error unregistering network callback: ${e.message}")
                }
            }
        }
    }

    companion object {
        private const val TAG = "IotWifiManager"
    }
}
