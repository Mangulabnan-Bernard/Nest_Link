package com.dtnmesh.app.audio

import android.content.Context
import android.media.MediaRecorder
import android.os.Build
import com.dtnmesh.app.dtn.DTNLogger
import java.io.File

/**
 * Grabación y compresión de audio para PTT.
 *
 * Codec seleccionado según API:
 *  - API 29+ (Android 10): Opus en contenedor OGG  → ~16 Kbps, excelente calidad de voz
 *  - API 26–28 (Android 8/9): AMR-WB              → ~23 Kbps, calidad HD Voice
 *
 * Comparación con PCM bruto anterior:
 *  - PCM 16kHz 16bit: ~256 Kbps (32 KB/s)
 *  - Opus: ~16 Kbps  (2 KB/s)  → 16x menos espacio en bundle
 *  - AMR-WB: ~23 Kbps (3 KB/s) → 11x menos espacio en bundle
 */
class OpusManager(private val context: Context) {
    private val TAG = "OpusManager"
    private var recorder: MediaRecorder? = null
    private var tempFile: File? = null
    var isRecording = false
        private set

    val useOpus get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    fun startRecording() {
        if (isRecording) return
        tempFile = File(context.cacheDir, "ptt_${System.currentTimeMillis()}.tmp")
        try {
            recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(context)
            } else {
                @Suppress("DEPRECATION") MediaRecorder()
            }
            recorder!!.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                if (useOpus) {
                    setOutputFormat(MediaRecorder.OutputFormat.OGG)
                    setAudioEncoder(MediaRecorder.AudioEncoder.OPUS)
                    setAudioSamplingRate(16000)
                    setAudioEncodingBitRate(16000)
                    DTNLogger.d(TAG, "Grabando con Opus/OGG (API ${Build.VERSION.SDK_INT})")
                } else {
                    setOutputFormat(MediaRecorder.OutputFormat.AMR_WB)
                    setAudioEncoder(MediaRecorder.AudioEncoder.AMR_WB)
                    setAudioSamplingRate(16000)
                    DTNLogger.d(TAG, "Grabando con AMR-WB (API ${Build.VERSION.SDK_INT})")
                }
                setAudioChannels(1)
                setOutputFile(tempFile!!.absolutePath)
                prepare()
                start()
            }
            isRecording = true
        } catch (e: Exception) {
            DTNLogger.e(TAG, "Error iniciando grabación: ${e.message}")
            releaseRecorder()
        }
    }

    fun stopRecording(): ByteArray {
        if (!isRecording) return ByteArray(0)
        isRecording = false
        return try {
            recorder?.stop()
            releaseRecorder()
            val bytes = tempFile?.readBytes() ?: ByteArray(0)
            DTNLogger.d(TAG, "Audio grabado: ${bytes.size / 1024}KB codec=${if (useOpus) "Opus" else "AMR-WB"}")
            bytes
        } catch (e: Exception) {
            DTNLogger.e(TAG, "Error deteniendo grabación: ${e.message}")
            ByteArray(0)
        } finally {
            tempFile?.delete()
            tempFile = null
        }
    }

    private fun releaseRecorder() {
        try { recorder?.release() } catch (_: Exception) {}
        recorder = null
    }

    /** Escribe el audio a un temp file para reproducirlo con MediaPlayer. */
    fun writeTempFile(audioBytes: ByteArray): File? {
        return try {
            val ext = if (useOpus) "ogg" else "amr"
            val f = File(context.cacheDir, "play_${System.currentTimeMillis()}.$ext")
            f.writeBytes(audioBytes)
            f
        } catch (e: Exception) {
            DTNLogger.e(TAG, "Error escribiendo temp file: ${e.message}")
            null
        }
    }
}
