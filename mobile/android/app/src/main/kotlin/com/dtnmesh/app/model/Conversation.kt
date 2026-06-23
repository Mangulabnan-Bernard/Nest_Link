package com.dtnmesh.app.model

data class Conversation(
    val peerEid: String,          // "broadcast" o EID del peer
    val displayName: String,      // nombre corto para mostrar
    val lastMessage: String,
    val lastMessageTime: Long,
    val isPeerOnline: Boolean = false
)
