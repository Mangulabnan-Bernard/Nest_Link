package com.dtnmesh.app.transport

import com.dtnmesh.app.model.BundleSummary
import com.dtnmesh.app.model.DTNBundle
import com.dtnmesh.app.model.PayloadType
import com.google.gson.Gson
import java.io.DataInputStream
import java.io.DataOutputStream

/**
 * Protocolo binario para intercambio de bundles DTN sobre sockets TCP/BT/Serial.
 *
 * Formato de mensaje:
 *  [tipo: 1 byte] [longitud_payload: 4 bytes] [payload: N bytes]
 *
 * Tipos:
 *  0x01 = HELLO            -> envía EID propio
 *  0x02 = BUNDLE_LIST      -> lista de IDs que tenemos (JSON)
 *  0x03 = BUNDLE_DATA      -> transferencia de bundle completo (JSON)
 *  0x04 = REQUEST_IDS      -> pedir lista de IDs del otro
 *  0x05 = BYE              -> cierre ordenado
 *  0x06 = KEY_EXCHANGE     -> clave pública EC P-256 (bytes X.509)
 *  0x07 = PROPHET_VECTOR   -> vector de probabilidades PRoPHET (JSON map)
 */
object BundleProtocol {
    const val MSG_HELLO: Byte = 0x01
    const val MSG_BUNDLE_LIST: Byte = 0x02
    const val MSG_BUNDLE_DATA: Byte = 0x03
    const val MSG_REQUEST_IDS: Byte = 0x04
    const val MSG_BYE: Byte = 0x05
    const val MSG_KEY_EXCHANGE: Byte = 0x06
    const val MSG_PROPHET_VECTOR: Byte = 0x07

    private val gson = Gson()

    fun writeHello(out: DataOutputStream, eid: String) {
        val bytes = eid.toByteArray()
        out.writeByte(MSG_HELLO.toInt())
        out.writeInt(bytes.size)
        out.write(bytes)
        out.flush()
    }

    fun writeBundleList(out: DataOutputStream, ids: List<String>) {
        val json = gson.toJson(ids)
        val bytes = json.toByteArray()
        out.writeByte(MSG_BUNDLE_LIST.toInt())
        out.writeInt(bytes.size)
        out.write(bytes)
        out.flush()
    }

    fun writeBundleData(out: DataOutputStream, bundle: DTNBundle) {
        val wire = WireBundle.fromBundle(bundle)
        val json = gson.toJson(wire)
        val bytes = json.toByteArray()
        out.writeByte(MSG_BUNDLE_DATA.toInt())
        out.writeInt(bytes.size)
        out.write(bytes)
        out.flush()
    }

    fun writeRequestIds(out: DataOutputStream) {
        out.writeByte(MSG_REQUEST_IDS.toInt())
        out.writeInt(0)
        out.flush()
    }

    fun writeBye(out: DataOutputStream) {
        out.writeByte(MSG_BYE.toInt())
        out.writeInt(0)
        out.flush()
    }

    fun writeKeyExchange(out: DataOutputStream, publicKeyBytes: ByteArray) {
        out.writeByte(MSG_KEY_EXCHANGE.toInt())
        out.writeInt(publicKeyBytes.size)
        out.write(publicKeyBytes)
        out.flush()
    }

    fun writeProphetVector(out: DataOutputStream, vector: Map<String, Float>) {
        val json = gson.toJson(vector)
        val bytes = json.toByteArray()
        out.writeByte(MSG_PROPHET_VECTOR.toInt())
        out.writeInt(bytes.size)
        out.write(bytes)
        out.flush()
    }

    fun parseProphetVector(payload: ByteArray): Map<String, Float> {
        return try {
            @Suppress("UNCHECKED_CAST")
            gson.fromJson(String(payload), Map::class.java) as Map<String, Float>
        } catch (_: Exception) { emptyMap() }
    }

    fun readMessage(input: DataInputStream): Pair<Byte, ByteArray>? {
        return try {
            val type = input.readByte()
            val length = input.readInt()
            val payload = if (length > 0) {
                val buf = ByteArray(length)
                input.readFully(buf)
                buf
            } else ByteArray(0)
            Pair(type, payload)
        } catch (e: Exception) {
            null
        }
    }

    fun parseEid(payload: ByteArray): String = String(payload)

    fun parseBundleList(payload: ByteArray): List<String> {
        return gson.fromJson(String(payload), Array<String>::class.java)?.toList() ?: emptyList()
    }

    fun parseBundle(payload: ByteArray): DTNBundle? {
        return try {
            val wire = gson.fromJson(String(payload), WireBundle::class.java)
            wire.toBundle()
        } catch (e: Exception) {
            null
        }
    }

    // Representación serializable del bundle (payload en base64)
    private data class WireBundle(
        val id: String,
        val sourceEid: String,
        val destEid: String,
        val payloadType: String,
        val payloadBase64: String,
        val ttlMillis: Long,
        val createdAt: Long,
        val hopCount: Int,
        val delivered: Boolean,
        val refBundleId: String?,
        val isEncrypted: Boolean = false
    ) {
        companion object {
            fun fromBundle(b: DTNBundle) = WireBundle(
                id = b.id,
                sourceEid = b.sourceEid,
                destEid = b.destEid,
                payloadType = b.payloadType.name,
                payloadBase64 = android.util.Base64.encodeToString(b.payload, android.util.Base64.NO_WRAP),
                ttlMillis = b.ttlMillis,
                createdAt = b.createdAt,
                hopCount = b.hopCount + 1,
                delivered = b.delivered,
                refBundleId = b.refBundleId,
                isEncrypted = b.isEncrypted
            )
        }

        fun toBundle() = DTNBundle(
            id = id,
            sourceEid = sourceEid,
            destEid = destEid,
            payloadType = PayloadType.valueOf(payloadType),
            payload = android.util.Base64.decode(payloadBase64, android.util.Base64.NO_WRAP),
            ttlMillis = ttlMillis,
            createdAt = createdAt,
            hopCount = hopCount,
            delivered = delivered,
            refBundleId = refBundleId,
            isEncrypted = isEncrypted
        )
    }
}
