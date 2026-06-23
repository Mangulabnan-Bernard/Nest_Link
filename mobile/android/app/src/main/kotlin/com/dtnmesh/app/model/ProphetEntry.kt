package com.dtnmesh.app.model

import androidx.room.Entity

@Entity(tableName = "prophet_entries", primaryKeys = ["localEid", "peerEid"])
data class ProphetEntry(
    val localEid: String,
    val peerEid: String,
    val probability: Float = 0f,
    val lastUpdated: Long = System.currentTimeMillis(),
    val contactCount: Int = 0
)
