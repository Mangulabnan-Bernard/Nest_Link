package com.dtnmesh.app.dtn

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

enum class LogLevel { DEBUG, INFO, WARN, ERROR, DTN }

data class LogEntry(
    val timestamp: Long = System.currentTimeMillis(),
    val level: LogLevel,
    val tag: String,
    val message: String
) {
    private val fmt = SimpleDateFormat("HH:mm:ss.SSS", Locale.getDefault())
    fun formatted(): String = "[${fmt.format(Date(timestamp))}] [${level.name}/${tag}] $message"
}

data class DTNMetrics(
    val bundlesSent: Int = 0,
    val bundlesReceived: Int = 0,
    val bundlesDelivered: Int = 0,
    val bundlesExpired: Int = 0,
    val bundlesInStore: Int = 0,
    val contactsTotal: Int = 0,
    val contactsCurrent: Int = 0,
    val lastContactDurationMs: Long = 0,
    val avgDeliveryTimeMs: Long = 0,
    val deliveryRatio: Float = 0f,
    val totalBytesTransferred: Long = 0
)

object DTNLogger {
    private const val MAX_ENTRIES = 500

    private val _logs = MutableStateFlow<List<LogEntry>>(emptyList())
    val logs: StateFlow<List<LogEntry>> = _logs.asStateFlow()

    private val _metrics = MutableStateFlow(DTNMetrics())
    val metrics: StateFlow<DTNMetrics> = _metrics.asStateFlow()

    private var bundlesSent = 0
    private var bundlesReceived = 0
    private var bundlesDelivered = 0
    private var bundlesExpired = 0
    private var contactsTotal = 0
    private var contactsCurrent = 0
    private var totalBytesTransferred = 0L
    private var deliveryTimes = mutableListOf<Long>()
    private var contactStartTime = 0L

    fun log(level: LogLevel, tag: String, message: String) {
        val entry = LogEntry(level = level, tag = tag, message = message)
        android.util.Log.d("DTNMesh[$tag]", message)
        val current = _logs.value.toMutableList()
        current.add(0, entry)
        if (current.size > MAX_ENTRIES) current.removeAt(current.size - 1)
        _logs.value = current
    }

    fun d(tag: String, msg: String) = log(LogLevel.DEBUG, tag, msg)
    fun i(tag: String, msg: String) = log(LogLevel.INFO, tag, msg)
    fun w(tag: String, msg: String) = log(LogLevel.WARN, tag, msg)
    fun e(tag: String, msg: String) = log(LogLevel.ERROR, tag, msg)
    fun dtn(tag: String, msg: String) = log(LogLevel.DTN, tag, msg)

    // Eventos DTN específicos
    fun onBundleCreated(bundleId: String, type: String, destEid: String) {
        dtn("BUNDLE", "Nuevo bundle creado: id=${bundleId.take(8)} tipo=$type dest=$destEid")
    }

    fun onBundleSent(bundleId: String, toPeer: String, bytes: Int) {
        bundlesSent++
        totalBytesTransferred += bytes
        dtn("ROUTING", "Bundle enviado: id=${bundleId.take(8)} peer=$toPeer bytes=$bytes")
        refreshMetrics()
    }

    fun onBundleReceived(bundleId: String, fromPeer: String, bytes: Int) {
        bundlesReceived++
        totalBytesTransferred += bytes
        dtn("ROUTING", "Bundle recibido: id=${bundleId.take(8)} peer=$fromPeer bytes=$bytes")
        refreshMetrics()
    }

    fun onBundleDelivered(bundleId: String, deliveryTimeMs: Long) {
        bundlesDelivered++
        deliveryTimes.add(deliveryTimeMs)
        dtn("DELIVERY", "Bundle entregado: id=${bundleId.take(8)} tiempo=${deliveryTimeMs}ms")
        refreshMetrics()
    }

    fun onBundleExpired(bundleId: String) {
        bundlesExpired++
        dtn("TTL", "Bundle expirado: id=${bundleId.take(8)}")
        refreshMetrics()
    }

    fun onContactEstablished(peerEid: String, address: String) {
        contactsTotal++
        contactsCurrent++
        contactStartTime = System.currentTimeMillis()
        dtn("CONTACT", "Contacto establecido: peer=$peerEid addr=$address (total=$contactsTotal)")
        refreshMetrics()
    }

    fun onContactLost(peerEid: String) {
        contactsCurrent = maxOf(0, contactsCurrent - 1)
        val duration = if (contactStartTime > 0) System.currentTimeMillis() - contactStartTime else 0
        dtn("CONTACT", "Contacto perdido: peer=$peerEid duración=${duration}ms")
        refreshMetrics()
    }

    fun onStoreUpdated(bundleCount: Int) {
        _metrics.value = _metrics.value.copy(bundlesInStore = bundleCount)
    }

    fun onEpidemicSync(peerEid: String, sentCount: Int, receivedCount: Int) {
        dtn("EPIDEMIC", "Sync epidémico con $peerEid: enviados=$sentCount recibidos=$receivedCount")
    }

    fun onTransportEvent(transport: String, event: String) {
        i("TRANSPORT", "[$transport] $event")
    }

    private fun refreshMetrics() {
        val avgDelivery = if (deliveryTimes.isNotEmpty()) deliveryTimes.average().toLong() else 0L
        val ratio = if (bundlesSent > 0) bundlesDelivered.toFloat() / bundlesSent.toFloat() else 0f
        _metrics.value = _metrics.value.copy(
            bundlesSent = bundlesSent,
            bundlesReceived = bundlesReceived,
            bundlesDelivered = bundlesDelivered,
            bundlesExpired = bundlesExpired,
            contactsTotal = contactsTotal,
            contactsCurrent = contactsCurrent,
            avgDeliveryTimeMs = avgDelivery,
            deliveryRatio = ratio,
            totalBytesTransferred = totalBytesTransferred
        )
    }

    fun clearLogs() {
        _logs.value = emptyList()
    }
}
