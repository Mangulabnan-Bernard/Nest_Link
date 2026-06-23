package com.dtnmesh.app.model

data class Peer(
    val eid: String,
    val name: String,
    val address: String = "",
    val lastSeen: Long = System.currentTimeMillis(),
    val isConnected: Boolean = false,
    val bundlesExchanged: Int = 0,
    val contactCount: Int = 0
)
