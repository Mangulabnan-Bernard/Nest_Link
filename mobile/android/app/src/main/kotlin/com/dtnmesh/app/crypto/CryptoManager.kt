package com.dtnmesh.app.crypto

import android.content.Context
import android.util.Base64
import com.dtnmesh.app.dtn.DTNLogger
import java.security.*
import java.security.spec.ECGenParameterSpec
import java.security.spec.X509EncodedKeySpec
import javax.crypto.Cipher
import javax.crypto.KeyAgreement
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Cifrado E2E: ECDH (P-256) + AES-256-GCM
 *
 * Flujo:
 *  1. Cada nodo genera un par de claves EC P-256 al arrancar (persiste en SharedPreferences).
 *  2. Al contactar un peer, se intercambian claves públicas (MSG_KEY_EXCHANGE en BundleProtocol).
 *  3. Se deriva un secreto compartido AES-256 via ECDH → SHA-256.
 *  4. Bundles TEXT/AUDIO se cifran con AES-256-GCM antes de almacenar y reenviar.
 *  5. Solo el destinatario (que tiene el shared secret) puede descifrar.
 *
 * Formato de ciphertext: [IV:12 bytes][datos cifrados + GCM tag:N+16 bytes]
 */
class CryptoManager(private val context: Context) {
    private val TAG = "Crypto"
    private val PREFS = "dtn_crypto"
    private val KEY_PRIVATE = "ec_private"
    private val KEY_PUBLIC = "ec_public"
    private val GCM_IV_LEN = 12
    private val GCM_TAG_LEN = 128 // bits

    private val prefs by lazy { context.getSharedPreferences(PREFS, Context.MODE_PRIVATE) }

    // Par de claves propio
    private val keyPair: KeyPair by lazy { loadOrGenerateKeyPair() }

    // Secretos compartidos derivados por ECDH, indexados por peerEid
    private val sharedSecrets = mutableMapOf<String, ByteArray>()

    // ────────────────────────────────────────────────────────────
    //  Clave propia
    // ────────────────────────────────────────────────────────────

    private fun loadOrGenerateKeyPair(): KeyPair {
        val privB64 = prefs.getString(KEY_PRIVATE, null)
        val pubB64 = prefs.getString(KEY_PUBLIC, null)
        return if (privB64 != null && pubB64 != null) {
            try {
                val kf = KeyFactory.getInstance("EC")
                val priv = kf.generatePrivate(java.security.spec.PKCS8EncodedKeySpec(Base64.decode(privB64, Base64.NO_WRAP)))
                val pub = kf.generatePublic(X509EncodedKeySpec(Base64.decode(pubB64, Base64.NO_WRAP)))
                KeyPair(pub, priv).also { DTNLogger.d(TAG, "Par de claves EC cargado") }
            } catch (e: Exception) {
                generateAndSaveKeyPair()
            }
        } else {
            generateAndSaveKeyPair()
        }
    }

    private fun generateAndSaveKeyPair(): KeyPair {
        val kg = KeyPairGenerator.getInstance("EC")
        kg.initialize(ECGenParameterSpec("secp256r1"), SecureRandom())
        val kp = kg.generateKeyPair()
        prefs.edit()
            .putString(KEY_PRIVATE, Base64.encodeToString(kp.private.encoded, Base64.NO_WRAP))
            .putString(KEY_PUBLIC, Base64.encodeToString(kp.public.encoded, Base64.NO_WRAP))
            .apply()
        DTNLogger.i(TAG, "Par de claves EC P-256 generado")
        return kp
    }

    /** Devuelve la clave pública propia en formato X.509 (para enviar al peer). */
    fun getPublicKeyBytes(): ByteArray = keyPair.public.encoded

    // ────────────────────────────────────────────────────────────
    //  Intercambio de claves con un peer
    // ────────────────────────────────────────────────────────────

    /**
     * Procesa la clave pública recibida de un peer.
     * Deriva y almacena el secreto compartido AES-256.
     */
    fun processPeerPublicKey(peerEid: String, peerPubKeyBytes: ByteArray) {
        try {
            val kf = KeyFactory.getInstance("EC")
            val peerPub = kf.generatePublic(X509EncodedKeySpec(peerPubKeyBytes))
            val ka = KeyAgreement.getInstance("ECDH")
            ka.init(keyPair.private)
            ka.doPhase(peerPub, true)
            val rawSecret = ka.generateSecret()
            // Derivar clave AES-256 via SHA-256
            val aesKey = MessageDigest.getInstance("SHA-256").digest(rawSecret)
            sharedSecrets[peerEid] = aesKey
            // Persistir para sesiones futuras
            prefs.edit().putString("peer_$peerEid", Base64.encodeToString(peerPubKeyBytes, Base64.NO_WRAP)).apply()
            DTNLogger.dtn(TAG, "Clave intercambiada con $peerEid — cifrado E2E activo")
        } catch (e: Exception) {
            DTNLogger.e(TAG, "Error procesando clave de $peerEid: ${e.message}")
        }
    }

    fun hasPeerKey(peerEid: String): Boolean {
        if (sharedSecrets.containsKey(peerEid)) return true
        // Intentar cargar de prefs si existe
        val b64 = prefs.getString("peer_$peerEid", null) ?: return false
        try {
            processPeerPublicKey(peerEid, Base64.decode(b64, Base64.NO_WRAP))
            return sharedSecrets.containsKey(peerEid)
        } catch (_: Exception) { return false }
    }

    // ────────────────────────────────────────────────────────────
    //  Cifrar / Descifrar
    // ────────────────────────────────────────────────────────────

    /**
     * Cifra [plaintext] con el secreto compartido del [peerEid].
     * Retorna null si no hay clave para ese peer.
     */
    fun encrypt(peerEid: String, plaintext: ByteArray): ByteArray? {
        val key = sharedSecrets[peerEid] ?: return null
        return try {
            val iv = ByteArray(GCM_IV_LEN).also { SecureRandom().nextBytes(it) }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(GCM_TAG_LEN, iv))
            val ciphertext = cipher.doFinal(plaintext)
            iv + ciphertext  // [IV:12][ciphertext+tag:N+16]
        } catch (e: Exception) {
            DTNLogger.e(TAG, "Error cifrando para $peerEid: ${e.message}")
            null
        }
    }

    /**
     * Descifra un payload cifrado con cualquiera de los secretos compartidos conocidos.
     * Intenta con todos hasta encontrar el correcto.
     */
    fun decrypt(ciphertext: ByteArray): ByteArray? {
        if (ciphertext.size < GCM_IV_LEN + 16) return null
        val iv = ciphertext.copyOfRange(0, GCM_IV_LEN)
        val data = ciphertext.copyOfRange(GCM_IV_LEN, ciphertext.size)
        for ((peerEid, key) in sharedSecrets) {
            try {
                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(GCM_TAG_LEN, iv))
                return cipher.doFinal(data)
            } catch (_: Exception) { /* clave incorrecta, probar la siguiente */ }
        }
        DTNLogger.w(TAG, "No se pudo descifrar: ninguna clave coincide")
        return null
    }
}
