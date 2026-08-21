package com.sphaerox.companion_app.network

import android.net.Network
import okhttp3.Dns
import okhttp3.OkHttpClient
import java.net.InetAddress
import java.util.concurrent.TimeUnit

object IotHttpClientFactory {

    private const val ESP32_SOFTAP_IP = "192.168.4.1"

    /**
     * Builds an OkHttpClient bound exclusively to the IoT Wi-Fi Network.
     * Cellular WAN (5G/LTE) is preserved for all other application network traffic!
     */
    fun createClient(iotNetwork: Network? = null): OkHttpClient {
        val builder = OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(120, TimeUnit.SECONDS)
            .writeTimeout(10, TimeUnit.SECONDS)
            .retryOnConnectionFailure(true)

        if (iotNetwork != null) {
            // 1. Direct all socket traffic through dedicated wlan0 interface
            builder.socketFactory(iotNetwork.socketFactory)
            // 2. DNS resolver bypass for local SoftAP IP
            builder.dns(object : Dns {
                override fun lookup(hostname: String): List<InetAddress> {
                    return if (hostname == "xiao.local" || hostname == "192.168.4.1") {
                        listOf(InetAddress.getByName(ESP32_SOFTAP_IP))
                    } else {
                        try {
                            iotNetwork.getAllByName(hostname).toList()
                        } catch (e: Exception) {
                            listOf(InetAddress.getByName(hostname))
                        }
                    }
                }
            })
        } else {
            builder.dns(object : Dns {
                override fun lookup(hostname: String): List<InetAddress> {
                    return if (hostname == "xiao.local" || hostname == "192.168.4.1") {
                        listOf(InetAddress.getByName(ESP32_SOFTAP_IP))
                    } else {
                        Dns.SYSTEM.lookup(hostname)
                    }
                }
            })
        }

        return builder.build()
    }
}
