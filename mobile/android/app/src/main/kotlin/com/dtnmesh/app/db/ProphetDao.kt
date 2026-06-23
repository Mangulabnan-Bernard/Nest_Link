package com.dtnmesh.app.db

import androidx.room.*
import com.dtnmesh.app.model.ProphetEntry

@Dao
interface ProphetDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entry: ProphetEntry)

    @Query("SELECT * FROM prophet_entries WHERE localEid = :localEid")
    suspend fun getAll(localEid: String): List<ProphetEntry>

    @Query("SELECT probability FROM prophet_entries WHERE localEid = :local AND peerEid = :peer")
    suspend fun getProbability(local: String, peer: String): Float?

    @Query("UPDATE prophet_entries SET probability = :p, lastUpdated = :t WHERE localEid = :local AND peerEid = :peer")
    suspend fun updateProbability(local: String, peer: String, p: Float, t: Long = System.currentTimeMillis())

    @Query("SELECT * FROM prophet_entries WHERE localEid = :local AND probability > 0.05")
    suspend fun getRelevant(local: String): List<ProphetEntry>
}
