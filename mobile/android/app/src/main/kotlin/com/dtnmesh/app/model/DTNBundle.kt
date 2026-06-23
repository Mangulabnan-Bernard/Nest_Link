package com.dtnmesh.app.model

import androidx.room.Entity
import androidx.room.PrimaryKey
import androidx.room.TypeConverter
import androidx.room.TypeConverters
import java.util.UUID

enum class PayloadType { TEXT, AUDIO, ACK, FRAGMENT }

@Entity(tableName = "bundles")
@TypeConverters(BundleConverters::class)
data class DTNBundle(
    @PrimaryKey
    val id: String = UUID.randomUUID().toString(),
    val sourceEid: String,
    val destEid: String,
    val payloadType: PayloadType,
    val payload: ByteArray,
    val ttlMillis: Long = 24 * 60 * 60 * 1000L,
    val createdAt: Long = System.currentTimeMillis(),
    val hopCount: Int = 0,
    val delivered: Boolean = false,
    val deliveredAt: Long? = null,
    val refBundleId: String? = null,   // para ACKs → bundle original; para FRAGMENT → bundle original
    val isEncrypted: Boolean = false   // payload cifrado con AES-256-GCM
) {
    fun isExpired(): Boolean = System.currentTimeMillis() > createdAt + ttlMillis
    fun ageMillis(): Long = System.currentTimeMillis() - createdAt
    fun summary(): BundleSummary = BundleSummary(id, sourceEid, destEid, payloadType, createdAt)

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        return id == (other as DTNBundle).id
    }
    override fun hashCode(): Int = id.hashCode()
}

data class BundleSummary(
    val id: String,
    val sourceEid: String,
    val destEid: String,
    val payloadType: PayloadType,
    val createdAt: Long
)

class BundleConverters {
    @TypeConverter fun fromPayloadType(v: PayloadType): String = v.name
    @TypeConverter fun toPayloadType(v: String): PayloadType = PayloadType.valueOf(v)
}
