package com.dtnmesh.app.dtn

import com.dtnmesh.app.db.BundleDao
import com.dtnmesh.app.model.BundleSummary
import com.dtnmesh.app.model.DTNBundle
import com.dtnmesh.app.model.PayloadType
import kotlinx.coroutines.flow.Flow

class BundleManager(private val dao: BundleDao, private val localEid: String) {

    val messagesFlow: Flow<List<DTNBundle>> = dao.getMessagesFlow()
    val pendingCountFlow: Flow<Int> = dao.getPendingCountFlow()
    val broadcastMessagesFlow: Flow<List<DTNBundle>> = dao.getBroadcastMessagesFlow()

    fun getDirectMessagesFlow(): Flow<List<DTNBundle>> = dao.getDirectMessagesFlow(localEid)
    fun getConversationFlow(peerEid: String): Flow<List<DTNBundle>> = dao.getConversationFlow(localEid, peerEid)

    suspend fun createTextBundle(text: String, destEid: String = "broadcast"): DTNBundle {
        val bundle = DTNBundle(
            sourceEid = localEid,
            destEid = destEid,
            payloadType = PayloadType.TEXT,
            payload = text.toByteArray(Charsets.UTF_8)
        )
        dao.insert(bundle)
        DTNLogger.onBundleCreated(bundle.id, "TEXT", destEid)
        return bundle
    }

    suspend fun createAudioBundle(audioBytes: ByteArray, destEid: String = "broadcast"): DTNBundle {
        val bundle = DTNBundle(
            sourceEid = localEid,
            destEid = destEid,
            payloadType = PayloadType.AUDIO,
            payload = audioBytes,
            ttlMillis = 2 * 60 * 60 * 1000L // 2 horas para audio
        )
        dao.insert(bundle)
        DTNLogger.onBundleCreated(bundle.id, "AUDIO", destEid)
        return bundle
    }

    suspend fun storeReceivedBundle(bundle: DTNBundle): Boolean {
        // No almacenar si ya tenemos este bundle
        if (dao.getById(bundle.id) != null) return false
        // No almacenar si ya expiró
        if (bundle.isExpired()) {
            DTNLogger.onBundleExpired(bundle.id)
            return false
        }
        // Marcar como entregado si es para nosotros
        val isForUs = bundle.destEid == localEid || bundle.destEid == "broadcast"
        val toStore = if (isForUs) {
            bundle.copy(delivered = true, deliveredAt = System.currentTimeMillis())
        } else {
            bundle
        }
        val result = dao.insert(toStore)
        if (result != -1L) {
            if (isForUs) {
                DTNLogger.onBundleDelivered(bundle.id, bundle.ageMillis())
            }
        }
        return result != -1L
    }

    suspend fun createAck(forBundleId: String, destEid: String): DTNBundle {
        val ack = DTNBundle(
            sourceEid = localEid,
            destEid = destEid,
            payloadType = PayloadType.ACK,
            payload = forBundleId.toByteArray(),
            ttlMillis = 60 * 60 * 1000L,
            refBundleId = forBundleId
        )
        dao.insert(ack)
        return ack
    }

    suspend fun processAck(ack: DTNBundle) {
        val refId = ack.refBundleId ?: String(ack.payload)
        val original = dao.getById(refId) ?: return
        dao.markDelivered(refId)
        DTNLogger.onBundleDelivered(refId, original.ageMillis())
    }

    suspend fun getPendingBundles(): List<DTNBundle> = dao.getPendingBundles()

    suspend fun getAllIds(): List<String> = dao.getAllIds()

    suspend fun getById(id: String): DTNBundle? = dao.getById(id)

    suspend fun purgeExpired(): Int {
        val pending = dao.getPendingBundles()
        var count = 0
        pending.filter { it.isExpired() }.forEach { bundle ->
            dao.markDelivered(bundle.id) // marcamos como entregado para que no se reenvíe
            DTNLogger.onBundleExpired(bundle.id)
            count++
        }
        dao.deleteExpired()
        val remaining = dao.getAllIds().size
        DTNLogger.onStoreUpdated(remaining)
        return count
    }

    suspend fun getMissingBundles(knownIds: List<String>): List<DTNBundle> {
        val pending = dao.getPendingBundles()
        return pending.filter { it.id !in knownIds && !it.isExpired() }
    }

    suspend fun markDelivered(bundleId: String) = dao.markDelivered(bundleId)

    /**
     * Elimina un bundle propio que todavía no fue entregado (ACK no recibido).
     * Retorna false si el bundle no existe, no es nuestro, o ya fue entregado.
     */
    suspend fun deleteOwnBundle(bundleId: String): Boolean {
        val bundle = dao.getById(bundleId) ?: return false
        if (bundle.sourceEid != localEid) return false
        if (bundle.delivered) return false
        dao.deleteById(bundleId)
        DTNLogger.i("BundleManager", "Bundle eliminado manualmente: $bundleId")
        return true
    }
}
