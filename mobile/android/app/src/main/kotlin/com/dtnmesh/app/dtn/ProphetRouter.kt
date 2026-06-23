package com.dtnmesh.app.dtn

import com.dtnmesh.app.db.ProphetDao
import com.dtnmesh.app.model.DTNBundle
import com.dtnmesh.app.model.ProphetEntry

/**
 * PRoPHET — Probabilistic Routing Protocol using History of Encounters and Transitivity
 * Referencia: Lindgren et al., "Probabilistic Routing in Intermittently Connected Networks"
 *
 * Parámetros:
 *  P_INIT  = 0.75  → predictibilidad inicial al conocer un nodo
 *  GAMMA   = 0.98  → factor de envejecimiento por intervalo
 *  BETA    = 0.25  → peso de transitividad
 *  AGING_INTERVAL = 5 min
 *
 * Ventaja sobre Epidémico:
 *  En lugar de reenviar TODOS los bundles a TODOS los nodos, solo reenvía
 *  cuando el peer tiene mayor probabilidad de entrega al destino.
 *  Esto reduce drásticamente el tráfico en redes con más de 3 nodos.
 */
class ProphetRouter(
    private val dao: ProphetDao,
    private val localEid: String
) {
    companion object {
        const val P_INIT = 0.75f
        const val GAMMA = 0.98f
        const val BETA = 0.25f
        const val AGING_INTERVAL_MS = 5 * 60 * 1000L
    }

    // ────────────────────────────────────────────────────────────
    //  Actualización al contactar un peer
    // ────────────────────────────────────────────────────────────

    /**
     * Llamar cuando se establece contacto con [peerEid].
     * Actualiza P(local, peer) y retorna la nueva probabilidad.
     */
    suspend fun onContact(peerEid: String): Float {
        val old = dao.getProbability(localEid, peerEid) ?: 0f
        val aged = applyAging(old, peerEid)
        val updated = aged + (1f - aged) * P_INIT
        val entry = dao.getAll(localEid).find { it.peerEid == peerEid }
        dao.upsert(ProphetEntry(
            localEid = localEid,
            peerEid = peerEid,
            probability = updated,
            contactCount = (entry?.contactCount ?: 0) + 1
        ))
        DTNLogger.dtn("PRoPHET", "P($localEid,$peerEid) ${old.fmt()} → ${updated.fmt()} (contactos: ${(entry?.contactCount ?: 0) + 1})")
        return updated
    }

    /**
     * Llamar cuando llega el vector de probabilidades del peer.
     * Actualiza transitividad: P(local,C) vía P(peer,C).
     */
    suspend fun updateTransitivity(peerEid: String, peerVector: Map<String, Float>) {
        val pAB = dao.getProbability(localEid, peerEid) ?: 0f
        var updated = 0
        for ((destEid, pBC) in peerVector) {
            if (destEid == localEid) continue
            val pAC_old = dao.getProbability(localEid, destEid) ?: 0f
            val pAC_new = maxOf(pAC_old, pAB * pBC * BETA)
            if (pAC_new > pAC_old + 0.001f) {
                dao.upsert(ProphetEntry(localEid = localEid, peerEid = destEid, probability = pAC_new))
                updated++
            }
        }
        if (updated > 0) DTNLogger.dtn("PRoPHET", "Transitividad vía $peerEid: $updated destinos actualizados")
    }

    // ────────────────────────────────────────────────────────────
    //  Decisión de reenvío
    // ────────────────────────────────────────────────────────────

    /**
     * ¿Debo reenviar [bundle] al peer [peerEid]?
     *
     * Regla PRoPHET: reenviar si P(peer, dest) > P(local, dest)
     * Excepciones: siempre reenviar si el peer ES el destino.
     */
    suspend fun shouldForward(bundle: DTNBundle, peerEid: String, peerVector: Map<String, Float>): Boolean {
        val dest = bundle.destEid
        // Broadcast: siempre reenviar
        if (dest == "broadcast") return true
        // El peer ES el destino
        if (dest == peerEid) return true
        val pLocal = dao.getProbability(localEid, dest) ?: 0f
        val pPeer = peerVector[dest] ?: 0f
        // Primer contacto con destino desconocido: ambos tienen P=0 → comportamiento epidémico (reenviar)
        val forward = pPeer > pLocal || (pLocal == 0f && pPeer == 0f)
        DTNLogger.d("PRoPHET", "Forward bundle→$dest via $peerEid? P(local)=${pLocal.fmt()} P(peer)=${pPeer.fmt()} → $forward")
        return forward
    }

    // ────────────────────────────────────────────────────────────
    //  Vector propio
    // ────────────────────────────────────────────────────────────

    /** Exporta el vector de probabilidades para enviar al peer. */
    suspend fun getProbabilityVector(): Map<String, Float> =
        dao.getRelevant(localEid).associate { it.peerEid to it.probability }

    // ────────────────────────────────────────────────────────────
    //  Envejecimiento
    // ────────────────────────────────────────────────────────────

    private suspend fun applyAging(oldP: Float, peerEid: String): Float {
        val entry = dao.getAll(localEid).find { it.peerEid == peerEid } ?: return oldP
        val elapsed = System.currentTimeMillis() - entry.lastUpdated
        val intervals = (elapsed / AGING_INTERVAL_MS).toInt().coerceAtLeast(0)
        if (intervals == 0) return oldP
        val aged = oldP * Math.pow(GAMMA.toDouble(), intervals.toDouble()).toFloat()
        return aged.coerceIn(0f, 1f)
    }

    /** Envejecimiento periódico de todas las entradas. */
    suspend fun ageAll() {
        val entries = dao.getAll(localEid)
        for (entry in entries) {
            val elapsed = System.currentTimeMillis() - entry.lastUpdated
            val intervals = (elapsed / AGING_INTERVAL_MS).toInt()
            if (intervals > 0) {
                val aged = (entry.probability * Math.pow(GAMMA.toDouble(), intervals.toDouble()).toFloat()).coerceIn(0f, 1f)
                dao.updateProbability(localEid, entry.peerEid, aged)
            }
        }
    }

    private fun Float.fmt() = "%.3f".format(this)
}
