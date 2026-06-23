package com.dtnmesh.app.db

import androidx.room.*
import com.dtnmesh.app.model.DTNBundle
import kotlinx.coroutines.flow.Flow

@Dao
interface BundleDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insert(bundle: DTNBundle): Long

    @Query("SELECT * FROM bundles WHERE delivered = 0 ORDER BY createdAt ASC")
    fun getPendingBundlesFlow(): Flow<List<DTNBundle>>

    @Query("SELECT * FROM bundles WHERE delivered = 0 ORDER BY createdAt ASC")
    suspend fun getPendingBundles(): List<DTNBundle>

    @Query("SELECT * FROM bundles ORDER BY createdAt DESC")
    fun getAllBundlesFlow(): Flow<List<DTNBundle>>

    @Query("SELECT * FROM bundles WHERE id = :id")
    suspend fun getById(id: String): DTNBundle?

    @Query("SELECT id FROM bundles")
    suspend fun getAllIds(): List<String>

    @Query("UPDATE bundles SET delivered = 1, deliveredAt = :time WHERE id = :id")
    suspend fun markDelivered(id: String, time: Long = System.currentTimeMillis())

    @Query("DELETE FROM bundles WHERE (createdAt + ttlMillis) < :now")
    suspend fun deleteExpired(now: Long = System.currentTimeMillis())

    @Query("SELECT COUNT(*) FROM bundles WHERE delivered = 0")
    fun getPendingCountFlow(): Flow<Int>

    @Query("SELECT * FROM bundles WHERE (destEid = :eid OR destEid = 'broadcast') AND delivered = 0")
    suspend fun getBundlesForEid(eid: String): List<DTNBundle>

    @Query("SELECT * FROM bundles WHERE payloadType IN ('TEXT','AUDIO') ORDER BY createdAt DESC")
    fun getMessagesFlow(): Flow<List<DTNBundle>>

    /** Todos los mensajes directos (no broadcast) donde participamos */
    @Query("SELECT * FROM bundles WHERE payloadType IN ('TEXT','AUDIO') AND destEid != 'broadcast' AND (sourceEid = :localEid OR destEid = :localEid) ORDER BY createdAt DESC")
    fun getDirectMessagesFlow(localEid: String): Flow<List<DTNBundle>>

    /** Conversación uno-a-uno con un peer específico */
    @Query("SELECT * FROM bundles WHERE payloadType IN ('TEXT','AUDIO') AND ((sourceEid = :localEid AND destEid = :peerEid) OR (sourceEid = :peerEid AND destEid = :localEid)) ORDER BY createdAt ASC")
    fun getConversationFlow(localEid: String, peerEid: String): Flow<List<DTNBundle>>

    /** Solo mensajes broadcast (grupo) */
    @Query("SELECT * FROM bundles WHERE payloadType IN ('TEXT','AUDIO') AND destEid = 'broadcast' ORDER BY createdAt ASC")
    fun getBroadcastMessagesFlow(): Flow<List<DTNBundle>>

    @Query("DELETE FROM bundles WHERE id = :id")
    suspend fun deleteById(id: String)

    @Query("DELETE FROM bundles")
    suspend fun deleteAll()
}
