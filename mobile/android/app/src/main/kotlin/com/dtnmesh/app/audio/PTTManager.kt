package com.dtnmesh.app.audio

import android.content.Context
import android.media.MediaPlayer
import com.dtnmesh.app.dtn.DTNLogger
import kotlinx.coroutines.*

class PTTManager(private val context: Context) {
    private val TAG = "PTT"
    private val opusManager = OpusManager(context)
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var recordingJob: Job? = null
    private var onDataCallback: ((ByteArray) -> Unit)? = null

    val isRecording get() = opusManager.isRecording

    fun startRecording(onData: (ByteArray) -> Unit) {
        if (isRecording) return
        onDataCallback = onData
        opusManager.startRecording()
        DTNLogger.d(TAG, "PTT: grabación iniciada (${if (opusManager.useOpus) "Opus" else "AMR-WB"})")
    }

    fun stopRecording() {
        if (!isRecording) return
        recordingJob = scope.launch {
            val bytes = opusManager.stopRecording()
            if (bytes.isNotEmpty()) {
                withContext(Dispatchers.Main) { onDataCallback?.invoke(bytes) }
            }
        }
    }

    fun playAudio(audioBytes: ByteArray) {
        if (audioBytes.isEmpty()) return
        scope.launch {
            val tempFile = opusManager.writeTempFile(audioBytes) ?: return@launch
            try {
                val player = MediaPlayer()
                player.setDataSource(tempFile.absolutePath)
                player.prepare()
                player.start()
                DTNLogger.d(TAG, "Reproduciendo audio: ${audioBytes.size / 1024}KB")
                player.setOnCompletionListener {
                    it.release()
                    tempFile.delete()
                }
            } catch (e: Exception) {
                DTNLogger.e(TAG, "Error reproduciendo: ${e.message}")
                tempFile.delete()
            }
        }
    }

    fun destroy() {
        opusManager.stopRecording()
        scope.cancel()
    }
}
