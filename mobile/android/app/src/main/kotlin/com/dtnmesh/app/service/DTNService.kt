package com.dtnmesh.app.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Binder
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import com.example.nest_link.MainActivity
import com.dtnmesh.app.audio.PTTManager
import com.dtnmesh.app.crypto.CryptoManager
import com.dtnmesh.app.db.AppDatabase
import com.dtnmesh.app.dtn.BundleManager
import com.dtnmesh.app.dtn.DTNLogger
import com.dtnmesh.app.dtn.FragmentManager
import com.dtnmesh.app.dtn.ProphetRouter
import com.dtnmesh.app.model.DTNBundle
import com.dtnmesh.app.model.PayloadType
import com.dtnmesh.app.transport.BluetoothTransport
import com.dtnmesh.app.transport.LoRaTransport
import com.dtnmesh.app.transport.WifiDirectManager
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow

class DTNService : LifecycleService() {
    companion object {
        const val NOTIF_CHANNEL_ID     = "dtn_service"
        const val NOTIF_CHANNEL_MSG_ID = "dtn_messages"
        const val NOTIF_ID             = 1001
        const val NOTIF_MSG_BASE_ID    = 2000
        const val EXTRA_PEER_EID       = "peer_eid"
        const val ACTION_STOP          = "com.dtnmesh.app.STOP"
        const val PREF_EID             = "local_eid"

        fun start(context: Context) = context.startForegroundService(Intent(context, DTNService::class.java))
        fun stop(context: Context) = context.startService(Intent(context, DTNService::class.java).apply { action = ACTION_STOP })
    }

    inner class LocalBinder : Binder() {
        fun getService(): DTNService = this@DTNService
    }

    private val binder = LocalBinder()
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    lateinit var bundleManager: BundleManager       private set
    lateinit var wifiDirectManager: WifiDirectManager  private set
    lateinit var bluetoothTransport: BluetoothTransport
        private set
    lateinit var pttManager: PTTManager
        private set
    lateinit var cryptoManager: CryptoManager
        private set
    lateinit var prophetRouter: ProphetRouter
        private set
    var loraTransport: LoRaTransport? = null
        private set

    lateinit var localEid: String
        private set

    private val _receivedBundles = MutableSharedFlow<DTNBundle>(extraBufferCapacity = 50)
    val receivedBundles: SharedFlow<DTNBundle> = _receivedBundles

    // Buffer de fragmentos recibidos, indexado por originalBundleId
    private val fragmentBuffer = mutableMapOf<String, MutableList<DTNBundle>>()

    private var wakeLock: PowerManager.WakeLock? = null
    private var purgeJob: Job? = null
    private var prophetAgeJob: Job? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()

        val prefs = getSharedPreferences("dtn_prefs", Context.MODE_PRIVATE)
        localEid = prefs.getString(PREF_EID, null) ?: run {
            val id = "DTN-" + android.provider.Settings.Secure.getString(
                contentResolver, android.provider.Settings.Secure.ANDROID_ID
            ).take(8).uppercase()
            prefs.edit().putString(PREF_EID, id).apply()
            id
        }
        DTNLogger.i("DTNService", "EID: $localEid")

        val db = AppDatabase.getInstance(this)
        bundleManager = BundleManager(db.bundleDao(), localEid)
        cryptoManager = CryptoManager(this)
        prophetRouter = ProphetRouter(db.prophetDao(), localEid)
        pttManager = PTTManager(this)

        wifiDirectManager = WifiDirectManager(
            context = this,
            localEid = localEid,
            bundleManager = bundleManager,
            prophetRouter = prophetRouter,
            cryptoManager = cryptoManager,
            onBundleReceived = ::handleReceivedBundle
        )

        bluetoothTransport = BluetoothTransport(
            context = this,
            localEid = localEid,
            bundleManager = bundleManager,
            prophetRouter = prophetRouter,
            cryptoManager = cryptoManager,
            onBundleReceived = ::handleReceivedBundle
        )

        // LoRa: inicializar solo si el módulo está presente
        loraTransport = LoRaTransport(
            context = this,
            localEid = localEid,
            bundleManager = bundleManager,
            onBundleReceived = ::handleReceivedBundle
        )

        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DTNMesh:WakeLock")
            .apply { acquire(10 * 60 * 1000L) }

        startForeground(NOTIF_ID, buildNotification("Iniciando…"))

        wifiDirectManager.initialize()
        wifiDirectManager.startDiscovery()
        bluetoothTransport.initialize()
        bluetoothTransport.startServer()
        bluetoothTransport.startDiscovery()
        loraTransport?.initialize()

        // Purga de bundles expirados cada 5 minutos
        purgeJob = scope.launch {
            while (isActive) {
                delay(5 * 60 * 1000L)
                val n = bundleManager.purgeExpired()
                if (n > 0) DTNLogger.i("DTNService", "Expirados eliminados: $n")
            }
        }
        // Envejecimiento PRoPHET cada 5 minutos
        prophetAgeJob = scope.launch {
            while (isActive) {
                delay(5 * 60 * 1000L)
                prophetRouter.ageAll()
            }
        }

        updateNotification("Buscando nodos…")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        if (intent?.action == ACTION_STOP) stopSelf()
        return START_STICKY
    }

    override fun onBind(intent: Intent): IBinder {
        super.onBind(intent)
        return binder
    }

    private suspend fun handleReceivedBundle(bundle: DTNBundle, fromPeer: String) {
        // Manejar fragmentos
        if (bundle.payloadType == PayloadType.FRAGMENT) {
            val meta = FragmentManager.parseMeta(bundle) ?: return
            val fragList = fragmentBuffer.getOrPut(meta.originalId) { mutableListOf() }
            if (fragList.none { FragmentManager.parseMeta(it)?.index == meta.index }) {
                fragList.add(bundle)
                bundleManager.storeReceivedBundle(bundle)
            }
            val reassembled = FragmentManager.tryReassemble(fragList)
            if (reassembled != null) {
                fragmentBuffer.remove(meta.originalId)
                handleReceivedBundle(reassembled, fromPeer)
            }
            return
        }

        // Descifrar si es necesario
        val finalBundle = if (bundle.isEncrypted) {
            val plain = cryptoManager.decrypt(bundle.payload)
            if (plain != null) bundle.copy(payload = plain, isEncrypted = false)
            else {
                DTNLogger.w("DTNService", "No se pudo descifrar bundle ${bundle.id.take(8)}")
                bundle  // guardar cifrado de todas formas (relay)
            }
        } else bundle

        // Un mensaje es "para nosotros" si destEid es nuestro EID, "broadcast",
        // o la MAC Wi-Fi Direct de este dispositivo (para compatibilidad con peers que envían por MAC)
        val localMac = wifiDirectManager.localMacAddress.value
        val isForUs = finalBundle.destEid == localEid
                   || finalBundle.destEid == "broadcast"
                   || (localMac.isNotEmpty() && finalBundle.destEid == localMac)

        // Si está dirigido a nuestra MAC, re-normalizar el destEid a nuestro EID antes de guardar
        val bundleToStore = if (isForUs && finalBundle.destEid == localMac) {
            finalBundle.copy(destEid = localEid)
        } else finalBundle

        val stored = bundleManager.storeReceivedBundle(bundleToStore)
        if (stored) {
            _receivedBundles.emit(bundleToStore)
            updateNotification("Bundle recibido de $fromPeer")
            // Only notify for real chats/audio from MY family — silence GPS/status
            // packets and other families' traffic.
            val payloadText = String(bundleToStore.payload, Charsets.UTF_8)
            val kind = envelopeKind(payloadText)
            val isChat = bundleToStore.payloadType == PayloadType.AUDIO ||
                (bundleToStore.payloadType == PayloadType.TEXT && (kind == "chat" || kind == "voice"))
            val fam = envelopeFamily(payloadText)
            val sameFamily = familyCode.isEmpty() || fam.isEmpty() || fam == familyCode
            if (isForUs && isChat && sameFamily) showMessageNotification(bundleToStore)
            if (bundleToStore.payloadType == PayloadType.ACK) {
                bundleManager.processAck(bundleToStore)
            } else if (isForUs) {
                scope.launch { bundleManager.createAck(bundleToStore.id, bundleToStore.sourceEid) }
            }
        }
    }

    fun updateNotification(status: String) {
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(NOTIF_ID, buildNotification(status))
    }

    /** Force a fresh discovery pass across Wi-Fi Direct + Bluetooth on demand. */
    fun rescan() {
        try { wifiDirectManager.refreshNow() } catch (_: Exception) {}
        try { bluetoothTransport.startDiscovery() } catch (_: Exception) {}
        updateNotification("Buscando nodos…")
    }

    /** Live radio-level connection state + detected devices, for the diagnostic. */
    fun meshStatus(): Map<String, Any> = mapOf(
        "wifiConnected" to wifiDirectManager.isConnected.value,
        "discoveredPeers" to wifiDirectManager.peers.value.size,
        "connectedAddress" to wifiDirectManager.connectedDeviceAddress.value,
        "peers" to wifiDirectManager.peers.value.map { d ->
            mapOf(
                "name" to (d.deviceName ?: ""),
                "address" to (d.deviceAddress ?: ""),
                "isDtn" to wifiDirectManager.peerEidMap.value.containsKey(d.deviceAddress),
                "status" to d.status // 0=connected 1=invited 2=failed 3=available 4=unavailable
            )
        }
    )

    private fun buildNotification(status: String) = NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
        .setContentTitle("DTN Mesh — $localEid")
        .setContentText(status)
        .setSmallIcon(android.R.drawable.ic_menu_share)
        .setOngoing(true)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .setContentIntent(PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE))
        .build()

    private fun showMessageNotification(bundle: DTNBundle) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val senderShort = bundle.sourceEid.take(12)
        val isUnicast = bundle.destEid == localEid
        val title = if (isUnicast) "Mensaje directo de $senderShort"
                    else "Mensaje en Grupo de $senderShort"
        val body = when (bundle.payloadType) {
            PayloadType.TEXT  -> envelopeChatText(String(bundle.payload, Charsets.UTF_8)).take(80)
            PayloadType.AUDIO -> "Audio (${bundle.payload.size / 1024}KB)"
            else              -> "Nuevo mensaje"
        }
        // Intent para abrir la conversación correcta al tocar la notificación
        val peerEid = if (isUnicast) bundle.sourceEid else "broadcast"
        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_PEER_EID, peerEid)
        }
        val pendingTap = PendingIntent.getActivity(this, peerEid.hashCode(), tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val notif = NotificationCompat.Builder(this, NOTIF_CHANNEL_MSG_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setSmallIcon(android.R.drawable.ic_menu_send)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pendingTap)
            .build()

        nm.notify(NOTIF_MSG_BASE_ID + peerEid.hashCode() % 100, notif)
    }

    /** Family code of the local user — notifications only fire for matching traffic. */
    @Volatile var familyCode: String = ""

    /** Reads the Nest Link envelope kind ("chat" / "status" / "loc"); defaults to chat. */
    private fun envelopeKind(text: String): String = try {
        org.json.JSONObject(text).optString("k", "chat")
    } catch (e: Exception) { "chat" }

    /** Reads the family code ("f") from an envelope; empty if absent/legacy. */
    private fun envelopeFamily(text: String): String = try {
        org.json.JSONObject(text).optString("f", "")
    } catch (e: Exception) { "" }

    /** Human-readable chat text from a Nest Link envelope ("Name: message"). */
    private fun envelopeChatText(text: String): String = try {
        val o = org.json.JSONObject(text)
        val n = o.optString("n", "")
        val body = if (o.optString("k", "chat") == "voice") "🎙️ Voice message" else o.optString("t", text)
        if (n.isNotEmpty()) "$n: $body" else body
    } catch (e: Exception) { text }

    private fun createNotificationChannel() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        // Canal de servicio (baja prioridad, persistente)
        nm.createNotificationChannel(
            NotificationChannel(NOTIF_CHANNEL_ID, "Servicio DTN Mesh", NotificationManager.IMPORTANCE_LOW)
                .apply { description = "Servicio en segundo plano" }
        )
        // Canal de mensajes (alta prioridad, heads-up)
        nm.createNotificationChannel(
            NotificationChannel(NOTIF_CHANNEL_MSG_ID, "Mensajes DTN", NotificationManager.IMPORTANCE_HIGH)
                .apply {
                    description = "Notificaciones de mensajes recibidos"
                    enableVibration(true)
                    enableLights(true)
                }
        )
    }

    override fun onDestroy() {
        super.onDestroy()
        purgeJob?.cancel(); prophetAgeJob?.cancel()
        wifiDirectManager.destroy()
        bluetoothTransport.destroy()
        loraTransport?.destroy()
        pttManager.destroy()
        wakeLock?.release()
        scope.cancel()
    }
}
