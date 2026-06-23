package com.dtnmesh.app.dtn

import com.dtnmesh.app.model.DTNBundle
import com.dtnmesh.app.model.PayloadType
import com.google.gson.Gson

/**
 * Fragmentación de bundles grandes para DTN.
 *
 * Bundles > MAX_SIZE se dividen en fragmentos que se enrutan independientemente.
 * Cada fragmento es un DTNBundle de tipo FRAGMENT con payload JSON que contiene:
 *  - originalId: ID del bundle original
 *  - originalType: tipo de payload (TEXT, AUDIO)
 *  - index: índice del fragmento (0-based)
 *  - total: total de fragmentos
 *  - data: bytes del fragmento en Base64
 *
 * Ventajas en DTN:
 *  - Fragmentos pequeños tienen mayor probabilidad de ser entregados en un solo contacto.
 *  - Cada fragmento puede tomar una ruta diferente (multipath DTN).
 */
object FragmentManager {
    const val MAX_FRAGMENT_SIZE = 32 * 1024   // 32 KB por fragmento
    private val gson = Gson()

    data class FragmentMeta(
        val originalId: String,
        val originalType: String,
        val index: Int,
        val total: Int,
        val dataB64: String
    )

    /**
     * Fragmenta un bundle si su payload supera MAX_FRAGMENT_SIZE.
     * Retorna lista con el bundle original si no necesita fragmentación,
     * o lista de DTNBundle tipo FRAGMENT en caso contrario.
     */
    fun maybeFragment(bundle: DTNBundle): List<DTNBundle> {
        if (bundle.payload.size <= MAX_FRAGMENT_SIZE) return listOf(bundle)
        val chunks = bundle.payload.toList().chunked(MAX_FRAGMENT_SIZE)
        val total = chunks.size
        DTNLogger.dtn("Frag", "Fragmentando bundle ${bundle.id.take(8)} en $total partes (${bundle.payload.size / 1024}KB total)")
        return chunks.mapIndexed { index, chunk ->
            val meta = FragmentMeta(
                originalId = bundle.id,
                originalType = bundle.payloadType.name,
                index = index,
                total = total,
                dataB64 = android.util.Base64.encodeToString(chunk.toByteArray(), android.util.Base64.NO_WRAP)
            )
            DTNBundle(
                sourceEid = bundle.sourceEid,
                destEid = bundle.destEid,
                payloadType = PayloadType.FRAGMENT,
                payload = gson.toJson(meta).toByteArray(),
                ttlMillis = bundle.ttlMillis,
                createdAt = bundle.createdAt,
                refBundleId = bundle.id,
                isEncrypted = bundle.isEncrypted
            )
        }
    }

    /**
     * Intenta rearmar un bundle a partir de los fragmentos recibidos.
     * Retorna el bundle completo si están todos los fragmentos, null en caso contrario.
     */
    fun tryReassemble(fragments: List<DTNBundle>): DTNBundle? {
        if (fragments.isEmpty()) return null
        val metas = fragments.mapNotNull { parseMeta(it) }
        if (metas.isEmpty()) return null
        val total = metas.first().total
        if (metas.size < total) return null  // faltan fragmentos
        val sorted = metas.sortedBy { it.index }
        if (sorted.map { it.index } != (0 until total).toList()) return null  // índices incompletos
        val payload = sorted.flatMap {
            android.util.Base64.decode(it.dataB64, android.util.Base64.NO_WRAP).toList()
        }.toByteArray()
        val firstFrag = fragments.first { parseMeta(it)?.index == 0 }
        val firstMeta = parseMeta(firstFrag)!!
        DTNLogger.dtn("Frag", "Bundle ${firstMeta.originalId.take(8)} reensamblado (${payload.size / 1024}KB)")
        return DTNBundle(
            id = firstMeta.originalId,
            sourceEid = firstFrag.sourceEid,
            destEid = firstFrag.destEid,
            payloadType = PayloadType.valueOf(firstMeta.originalType),
            payload = payload,
            ttlMillis = firstFrag.ttlMillis,
            createdAt = firstFrag.createdAt,
            refBundleId = firstFrag.refBundleId,
            isEncrypted = firstFrag.isEncrypted
        )
    }

    fun parseMeta(bundle: DTNBundle): FragmentMeta? {
        if (bundle.payloadType != PayloadType.FRAGMENT) return null
        return try { gson.fromJson(String(bundle.payload), FragmentMeta::class.java) }
        catch (_: Exception) { null }
    }

    /** Agrupa fragmentos recibidos por originalId para intentar reensamblado. */
    fun groupFragments(bundles: List<DTNBundle>): Map<String, List<DTNBundle>> =
        bundles.filter { it.payloadType == PayloadType.FRAGMENT }
            .groupBy { parseMeta(it)?.originalId ?: "" }
            .filter { it.key.isNotEmpty() }
}
