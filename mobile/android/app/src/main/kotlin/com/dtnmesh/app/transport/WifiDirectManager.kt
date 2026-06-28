package com.dtnmesh.app.transport

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.NetworkInfo
import android.net.wifi.p2p.*
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceInfo
import android.net.wifi.p2p.nsd.WifiP2pDnsSdServiceRequest
import android.os.Build
import com.dtnmesh.app.crypto.CryptoManager
import com.dtnmesh.app.dtn.BundleManager
import com.dtnmesh.app.dtn.DTNLogger
import com.dtnmesh.app.dtn.FragmentManager
import com.dtnmesh.app.dtn.ProphetRouter
import com.dtnmesh.app.model.DTNBundle
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket

@SuppressLint("MissingPermission")
class WifiDirectManager(
    private val context: Context,
    private val localEid: String,
    private val bundleManager: BundleManager,
    private val prophetRouter: ProphetRouter,
    private val cryptoManager: CryptoManager,
    private val onBundleReceived: suspend (DTNBundle, String) -> Unit
) {
    private val TAG = "WiFiDirect"
    private val SERVICE_TYPE = "_dtnmesh._tcp"
    private val SERVICE_PORT = 8765

    private val manager: WifiP2pManager by lazy {
        context.getSystemService(Context.WIFI_P2P_SERVICE) as WifiP2pManager
    }
    private lateinit var channel: WifiP2pManager.Channel

    private val _peers = MutableStateFlow<List<WifiP2pDevice>>(emptyList())
    val peers: StateFlow<List<WifiP2pDevice>> = _peers

    private val _isGroupOwner = MutableStateFlow(false)
    val isGroupOwner: StateFlow<Boolean> = _isGroupOwner

    private val _groupOwnerAddress = MutableStateFlow("")
    val groupOwnerAddress: StateFlow<String> = _groupOwnerAddress

    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    private val _connectedDeviceAddress = MutableStateFlow("")
    val connectedDeviceAddress: StateFlow<String> = _connectedDeviceAddress

    /** Mapeo MAC → DTN EID, poblado desde DNS-SD y HELLO exchange */
    private val _peerEidMap = MutableStateFlow<Map<String, String>>(emptyMap())
    val peerEidMap: StateFlow<Map<String, String>> = _peerEidMap

    /** MAC Wi-Fi Direct de este dispositivo (para reconocer mensajes dirigidos a nuestra MAC) */
    private val _localMacAddress = MutableStateFlow("")
    val localMacAddress: StateFlow<String> = _localMacAddress

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var serverJob: Job? = null
    private var connectedPeerEid: String = ""
    /** MACs de dispositivos que fallaron el handshake DTN (TV, impresoras, etc.) — no reintentar */
    private val nonDtnDevices = mutableSetOf<String>()
    /** Contador de fallos de manager.connect() por MAC */
    private val connectFailCount = mutableMapOf<String, Int>()
    /** Timestamp del último intento de conexión (para cooldown) */
    @Volatile private var lastConnectAttemptMs = 0L
    /** Job de retry único — cancela el anterior antes de programar uno nuevo */
    private var retryJob: Job? = null
    /** Timestamp de inicio del servicio, para retry agresivo en los primeros 30s */
    private val startTimeMs = System.currentTimeMillis()

    private val prefs by lazy { context.getSharedPreferences("dtn_peer_cache", Context.MODE_PRIVATE) }
    private val PREFS_EID_MAP = "eid_map_json"

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                    val state = intent.getIntExtra(WifiP2pManager.EXTRA_WIFI_STATE, -1)
                    DTNLogger.onTransportEvent(TAG, "Estado WiFi P2P: $state")
                }
                WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                    manager.requestPeers(channel) { peerList ->
                        val devices = peerList.deviceList.toList()
                        _peers.value = devices
                        DTNLogger.d(TAG, "Peers encontrados: ${devices.size}")
                        // Fallback: solo si somos el iniciador (EID mayor) y hay peer DTN conocido
                        val now = System.currentTimeMillis()
                        if (!_isConnected.value && _connectedDeviceAddress.value.isEmpty()
                            && (now - lastConnectAttemptMs) > 8000) {
                            val knownDtnMacs = _peerEidMap.value.keys
                            val target = devices.firstOrNull { it.deviceAddress in knownDtnMacs
                                && (_peerEidMap.value[it.deviceAddress] ?: "") < localEid }
                            if (target != null) {
                                val peerEid = _peerEidMap.value[target.deviceAddress] ?: ""
                                DTNLogger.i(TAG, "Fallback DTN → ${target.deviceName} ($peerEid) [soy iniciador]")
                                lastConnectAttemptMs = now
                                _connectedDeviceAddress.value = target.deviceAddress
                                scope.launch { connectToDevice(target) }
                            }
                        }
                    }
                }
                WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                    val networkInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(WifiP2pManager.EXTRA_NETWORK_INFO, NetworkInfo::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(WifiP2pManager.EXTRA_NETWORK_INFO) as? NetworkInfo
                    }
                    if (networkInfo?.isConnected == true) {
                        manager.requestConnectionInfo(channel) { info ->
                            handleConnectionInfo(info)
                        }
                    } else {
                        val disconnectedMac = _connectedDeviceAddress.value
                        val hadP2pConnection = _isConnected.value
                        if (hadP2pConnection) {
                            DTNLogger.onContactLost(connectedPeerEid.ifEmpty { "desconocido" })
                        }
                        _isConnected.value = false
                        _connectedDeviceAddress.value = ""
                        serverJob?.cancel()
                        // Solo blacklistear si el grupo P2P SE FORMÓ (hadP2pConnection=true)
                        // pero nunca hubo handshake DTN. Si el grupo nunca se formó, podría
                        // ser un evento stale o colisión de conexión — no blacklistear.
                        if (hadP2pConnection
                            && disconnectedMac.isNotEmpty()
                            && disconnectedMac !in _peerEidMap.value
                            && connectedPeerEid.isEmpty()) {
                            DTNLogger.w(TAG, "Peer $disconnectedMac: grupo formado sin handshake DTN — descartando")
                            nonDtnDevices.add(disconnectedMac)
                        }
                        connectedPeerEid = ""
                        // Reiniciar descubrimiento inmediatamente tras perder conexión
                        scope.launch { delay(2000); discoverPeersFallback() }
                    }
                }
                WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION -> {
                    val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE, WifiP2pDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_DEVICE) as? WifiP2pDevice
                    }
                    device?.deviceAddress?.let { _localMacAddress.value = it }
                }
            }
        }
    }

    fun initialize() {
        channel = manager.initialize(context, context.mainLooper, null)
        val filter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }
        context.registerReceiver(receiver, filter)
        loadCachedEidMap()
        DTNLogger.i(TAG, "WiFi Direct inicializado. EID local: $localEid")
    }

    /** Carga el mapa MAC→EID persistido de sesiones anteriores. */
    private fun loadCachedEidMap() {
        val json = prefs.getString(PREFS_EID_MAP, null) ?: return
        try {
            val map = mutableMapOf<String, String>()
            // Formato: "MAC1=EID1,MAC2=EID2"
            json.split(",").forEach { entry ->
                val idx = entry.indexOf('=')
                if (idx > 0) map[entry.substring(0, idx)] = entry.substring(idx + 1)
            }
            if (map.isNotEmpty()) {
                _peerEidMap.value = map
                DTNLogger.i(TAG, "Mapa EID cargado del caché: ${map.size} peers")
            }
        } catch (_: Exception) {}
    }

    /** Agrega un par MAC→EID al mapa y lo persiste. */
    private fun addToEidMap(mac: String, eid: String) {
        if (mac.isEmpty() || eid.isEmpty()) return
        val updated = _peerEidMap.value + (mac to eid)
        _peerEidMap.value = updated
        val json = updated.entries.joinToString(",") { "${it.key}=${it.value}" }
        prefs.edit().putString(PREFS_EID_MAP, json).apply()
    }

    fun startDiscovery() {
        registerService()
        discoverServices()
        scope.launch {
            // Fase agresiva: reintentar cada 10s durante los primeros 60s de vida
            while (isActive && System.currentTimeMillis() - startTimeMs < 60_000) {
                delay(10_000)
                if (!_isConnected.value) {
                    DTNLogger.d(TAG, "Re-descubrimiento rápido (arranque)")
                    // Intentar conectar con peers cacheados directamente antes del DNS-SD
                    tryCachedPeerConnect()
                    discoverServices()
                }
            }
            // Fase normal: cada 60s
            while (isActive) {
                delay(60_000)
                if (!_isConnected.value) {
                    DTNLogger.d(TAG, "Re-descubrimiento periódico")
                    withContext(Dispatchers.Main) {
                        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
                            override fun onSuccess() { }
                            override fun onFailure(r: Int) { }
                        })
                    }
                    delay(1000)
                    discoverServices()
                }
            }
        }
    }

    /**
     * Intenta conectar con peers conocidos del caché sin esperar DNS-SD.
     * Solo usa MACs del mapa cacheado que ya sabemos que son DTN y donde somos iniciadores.
     */
    /** On-demand refresh for the "Search" button: re-advertise, re-scan, and
     *  immediately try any cached peers (faster than waiting for the next cycle). */
    fun refreshNow() {
        registerService()
        discoverServices()
        tryCachedPeerConnect()
    }

    private fun tryCachedPeerConnect() {
        if (_isConnected.value || _connectedDeviceAddress.value.isNotEmpty()) return
        val cachedDtnPeers = _peerEidMap.value.filter { (_, eid) ->
            eid.startsWith("DTN-") && localEid > eid
        }
        if (cachedDtnPeers.isEmpty()) return
        val now = System.currentTimeMillis()
        if ((now - lastConnectAttemptMs) < 8000) return
        // Buscar si alguno de los peers cacheados está en la lista de peers Wi-Fi Direct activos
        val activePeers = _peers.value
        val target = activePeers.firstOrNull { it.deviceAddress in cachedDtnPeers }
        if (target != null) {
            val peerEid = cachedDtnPeers[target.deviceAddress] ?: return
            DTNLogger.i(TAG, "Conectando con peer cacheado ${target.deviceName} ($peerEid)")
            lastConnectAttemptMs = now
            _connectedDeviceAddress.value = target.deviceAddress
            scope.launch { connectToDevice(target) }
        } else {
            // Peer cacheado no visible aún — lanzar discoverPeers para que aparezca
            discoverPeersFallback()
        }
    }

    private fun registerService() {
        val record = mapOf("eid" to localEid, "version" to "1")
        val serviceInfo = WifiP2pDnsSdServiceInfo.newInstance("DTNMesh-$localEid", SERVICE_TYPE, record)
        manager.addLocalService(channel, serviceInfo,
            object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    DTNLogger.i(TAG, "Servicio DTN registrado para descubrimiento")
                }
                override fun onFailure(reason: Int) {
                    DTNLogger.w(TAG, "Error registrando servicio: $reason")
                }
            })
    }

    private fun discoverServices() {
        manager.setDnsSdResponseListeners(channel,
            { instanceName, _, device ->
                if (instanceName.startsWith("DTNMesh-")) {
                    val peerEid = instanceName.removePrefix("DTNMesh-")
                    val mac = device.deviceAddress
                    // Registrar en mapa ANTES de cualquier intento de conexión
                    addToEidMap(mac, peerEid)
                    // Nunca es non-DTN: si estaba blacklisteado por error, sacarlo
                    nonDtnDevices.remove(mac)
                    DTNLogger.i(TAG, "Servicio DTN encontrado: $instanceName en $mac")
                    // Solo el EID MAYOR inicia la conexión P2P. El EID menor nunca llama
                    // manager.connect() — solo espera. Esto elimina colisiones 100%.
                    if (localEid > peerEid) {
                        val now = System.currentTimeMillis()
                        if (!_isConnected.value && _connectedDeviceAddress.value.isEmpty()
                            && (now - lastConnectAttemptMs) > 5000) {
                            DTNLogger.i(TAG, "Iniciando conexión a ${device.deviceName} ($mac) [soy iniciador]")
                            lastConnectAttemptMs = now
                            _connectedDeviceAddress.value = mac
                            scope.launch { connectToDevice(device) }
                        }
                    } else {
                        DTNLogger.d(TAG, "Esperando conexión de ${device.deviceName} [soy servidor]")
                    }
                }
            },
            { _, record, device ->
                val peerEid = record["eid"]
                if (peerEid != null) {
                    addToEidMap(device.deviceAddress, peerEid)
                    nonDtnDevices.remove(device.deviceAddress)
                    DTNLogger.d(TAG, "DNS-SD TXT: MAC ${device.deviceAddress} → EID $peerEid")
                }
            }
        )

        val request = WifiP2pDnsSdServiceRequest.newInstance(SERVICE_TYPE)
        manager.addServiceRequest(channel, request,
            object : WifiP2pManager.ActionListener {
                override fun onSuccess() {
                    manager.discoverServices(channel, object : WifiP2pManager.ActionListener {
                        override fun onSuccess() {
                            DTNLogger.i(TAG, "Descubrimiento de servicios iniciado")
                        }
                        override fun onFailure(reason: Int) {
                            DTNLogger.w(TAG, "Error en discoverServices: $reason — intentando discoverPeers")
                            discoverPeersFallback()
                        }
                    })
                }
                override fun onFailure(reason: Int) {
                    DTNLogger.w(TAG, "Error addServiceRequest: $reason")
                    discoverPeersFallback()
                }
            })
    }

    private fun discoverPeersFallback() {
        manager.discoverPeers(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = DTNLogger.i(TAG, "Descubrimiento de peers iniciado (fallback)")
            override fun onFailure(reason: Int) = DTNLogger.w(TAG, "Error discoverPeers: $reason")
        })
    }

    private fun connectToDevice(device: WifiP2pDevice) {
        val config = WifiP2pConfig().apply {
            deviceAddress = device.deviceAddress
            wps.setup = android.net.wifi.WpsInfo.PBC
            groupOwnerIntent = 0  // Iniciador prefiere ser cliente; el peer será GO
        }
        DTNLogger.i(TAG, "Conectando a ${device.deviceName} (${device.deviceAddress})")
        manager.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = DTNLogger.d(TAG, "Solicitud de conexión enviada")
            override fun onFailure(reason: Int) {
                DTNLogger.w(TAG, "Error de conexión a ${device.deviceName}: reason=$reason")
                val mac = device.deviceAddress
                val isDtnPeer = mac in _peerEidMap.value
                if (isDtnPeer) {
                    // ERROR(0) o BUSY(2): peer ocupado. Un único job de retry — cancelar el anterior.
                    if (reason == WifiP2pManager.ERROR || reason == 2 /* BUSY */) {
                        val peerEidForRetry = _peerEidMap.value[mac] ?: ""
                        if (_connectedDeviceAddress.value == mac) _connectedDeviceAddress.value = ""
                        // Solo reintenta si somos el iniciador
                        if (localEid > peerEidForRetry) {
                            DTNLogger.i(TAG, "Peer DTN $mac no disponible (reason=$reason), reintentando en 15s")
                            retryJob?.cancel()
                            retryJob = scope.launch {
                                delay(15_000)
                                if (!_isConnected.value && _connectedDeviceAddress.value.isEmpty()) {
                                    lastConnectAttemptMs = System.currentTimeMillis()
                                    _connectedDeviceAddress.value = mac
                                    DTNLogger.i(TAG, "Reintentando conexión DTN a $mac")
                                    connectToDevice(device)
                                }
                            }
                        }
                    }
                } else {
                    val count = (connectFailCount[mac] ?: 0) + 1
                    connectFailCount[mac] = count
                    if (count >= 3) {
                        DTNLogger.i(TAG, "Descartando ${device.deviceName} tras $count fallos")
                        nonDtnDevices.add(mac)
                    }
                    if (_connectedDeviceAddress.value == mac) _connectedDeviceAddress.value = ""
                }
            }
        })
    }

    private fun handleConnectionInfo(info: WifiP2pInfo) {
        _isGroupOwner.value = info.isGroupOwner
        val ownerAddr = info.groupOwnerAddress?.hostAddress ?: "192.168.49.1"
        _groupOwnerAddress.value = ownerAddr
        _isConnected.value = true
        connectedPeerEid = "" // reset para nueva sesión

        DTNLogger.i(TAG, "Conectado. GroupOwner=${info.isGroupOwner} ownerAddr=$ownerAddr")

        if (info.isGroupOwner) {
            startSocketServer()
        } else {
            scope.launch {
                delay(2500) // esperar que el servidor esté listo (T-Beam/Android puede tardar)
                connectAsClient(ownerAddr)
            }
        }
    }

    private fun startSocketServer() {
        serverJob = scope.launch {
            DTNLogger.i(TAG, "Iniciando servidor DTN en puerto $SERVICE_PORT")
            try {
                val serverSocket = ServerSocket(SERVICE_PORT)
                // Timeout: si nadie conecta en 20s, el peer no tiene DTN → descartar
                serverSocket.soTimeout = 20_000
                var gotConnection = false
                try {
                    while (isActive) {
                        val client = serverSocket.accept()
                        gotConnection = true
                        DTNLogger.onTransportEvent(TAG, "Cliente conectado desde ${client.inetAddress.hostAddress}")
                        launch { handleSession(client, isInitiator = false) }
                    }
                } catch (e: java.net.SocketTimeoutException) {
                    if (!gotConnection) {
                        // Nadie se conectó — el peer no tiene DTN. Descartarlo y salir del grupo.
                        val failedMac = _connectedDeviceAddress.value
                        if (failedMac.isNotEmpty()) {
                            DTNLogger.w(TAG, "Timeout servidor — $failedMac no es nodo DTN, descartando")
                            nonDtnDevices.add(failedMac)
                        }
                        _isConnected.value = false
                        _connectedDeviceAddress.value = ""
                        withContext(Dispatchers.Main) {
                            manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
                                override fun onSuccess() {
                                    scope.launch { delay(1000); discoverPeersFallback() }
                                }
                                override fun onFailure(r: Int) = Unit
                            })
                        }
                    }
                } finally {
                    try { serverSocket.close() } catch (_: Exception) {}
                }
            } catch (e: Exception) {
                DTNLogger.e(TAG, "Error en servidor: ${e.message}")
            }
        }
    }

    private suspend fun connectAsClient(ownerAddress: String) {
        var consecutiveFailures = 0
        // Bucle de sesiones: mientras la conexión P2P esté activa, re-conectar cada 5s
        // para transferir bundles nuevos acumulados durante la sesión anterior.
        while (_isConnected.value) {
            try {
                DTNLogger.i(TAG, "Conectando como cliente a $ownerAddress:$SERVICE_PORT")
                val socket = Socket()
                socket.connect(InetSocketAddress(ownerAddress, SERVICE_PORT), 5000)
                val (s, r) = handleSession(socket, isInitiator = true)
                consecutiveFailures = 0
                // Reconectar rápido si hubo intercambio (puede haber más), sino esperar más
                delay(if (s > 0 || r > 0) 5000L else 20_000L)
            } catch (e: Exception) {
                consecutiveFailures++
                DTNLogger.w(TAG, "Error cliente (fallo $consecutiveFailures): ${e.message}")
                if (consecutiveFailures >= 3) break
                delay(2000)
            }
        }
        if (consecutiveFailures >= 3) {
            // Varios fallos TCP seguidos — no es un nodo DTN o el grupo cayó. Salir.
            val failedMac = _connectedDeviceAddress.value
            DTNLogger.w(TAG, "Peer $failedMac no responde tras $consecutiveFailures intentos, descartando")
            if (failedMac.isNotEmpty() && failedMac !in _peerEidMap.value) nonDtnDevices.add(failedMac)
            _isConnected.value = false
            _connectedDeviceAddress.value = ""
            withContext(Dispatchers.Main) {
                manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
                    override fun onSuccess() {
                        DTNLogger.i(TAG, "Grupo P2P removido, reiniciando descubrimiento")
                        scope.launch { delay(2000); discoverPeersFallback() }
                    }
                    override fun onFailure(r: Int) = DTNLogger.w(TAG, "Error removiendo grupo: $r")
                })
            }
        }
    }

    private suspend fun prepareBundlesToSend(
        peerIds: List<String>,
        peerEid: String,
        peerVector: Map<String, Float>
    ): List<DTNBundle> {
        val candidates = bundleManager.getMissingBundles(peerIds)
        val toSend = candidates.filter { prophetRouter.shouldForward(it, peerEid, peerVector) }
        val fragmented = toSend.flatMap { FragmentManager.maybeFragment(it) }
        DTNLogger.dtn("PRoPHET", "Sesión con $peerEid: ${candidates.size} candidatos → ${toSend.size} por PRoPHET → ${fragmented.size} con fragmentación")
        return fragmented
    }

    private suspend fun handleSession(socket: Socket, isInitiator: Boolean): Pair<Int,Int> {
        var peerEid = ""
        var sent = 0
        var received = 0
        try {
            socket.soTimeout = 15000
            val out = DataOutputStream(socket.getOutputStream())
            val inp = DataInputStream(socket.getInputStream())

            // 1. HELLO
            BundleProtocol.writeHello(out, localEid)
            val msg1 = BundleProtocol.readMessage(inp) ?: return Pair(0, 0)
            if (msg1.first == BundleProtocol.MSG_HELLO) {
                peerEid = BundleProtocol.parseEid(msg1.second)
                connectedPeerEid = peerEid
                if (_connectedDeviceAddress.value.isNotEmpty()) {
                    addToEidMap(_connectedDeviceAddress.value, peerEid)
                } else {
                    val knownMac = _peerEidMap.value.entries.firstOrNull { it.value == peerEid }?.key
                    if (knownMac != null) {
                        _connectedDeviceAddress.value = knownMac
                    }
                }
                DTNLogger.onContactEstablished(peerEid, socket.inetAddress.hostAddress ?: "")
            } else return Pair(0, 0)

            // 2. KEY_EXCHANGE — cifrado E2E
            BundleProtocol.writeKeyExchange(out, cryptoManager.getPublicKeyBytes())
            val msg2 = BundleProtocol.readMessage(inp) ?: return Pair(0, 0)
            if (msg2.first == BundleProtocol.MSG_KEY_EXCHANGE) {
                cryptoManager.processPeerPublicKey(peerEid, msg2.second)
            }

            // 3. PROPHET_VECTOR — routing probabilístico
            prophetRouter.onContact(peerEid)
            val localVector = prophetRouter.getProbabilityVector()
            BundleProtocol.writeProphetVector(out, localVector)
            val msg3 = BundleProtocol.readMessage(inp) ?: return Pair(0, 0)
            var peerVector = emptyMap<String, Float>()
            if (msg3.first == BundleProtocol.MSG_PROPHET_VECTOR) {
                peerVector = BundleProtocol.parseProphetVector(msg3.second)
                prophetRouter.updateTransitivity(peerEid, peerVector)
            }

            // 4. BUNDLE_LIST — intercambio simultáneo de listas (evita deadlock)
            var bundlesToSend: List<DTNBundle> = emptyList()
            if (isInitiator) {
                BundleProtocol.writeBundleList(out, bundleManager.getAllIds())
                val msg4 = BundleProtocol.readMessage(inp) ?: return Pair(0, 0)
                if (msg4.first == BundleProtocol.MSG_BUNDLE_LIST) {
                    val peerIds = BundleProtocol.parseBundleList(msg4.second)
                    bundlesToSend = prepareBundlesToSend(peerIds, peerEid, peerVector)
                }
            } else {
                val msg4 = BundleProtocol.readMessage(inp) ?: return Pair(0, 0)
                BundleProtocol.writeBundleList(out, bundleManager.getAllIds())
                if (msg4.first == BundleProtocol.MSG_BUNDLE_LIST) {
                    val peerIds = BundleProtocol.parseBundleList(msg4.second)
                    bundlesToSend = prepareBundlesToSend(peerIds, peerEid, peerVector)
                }
            }

            // 5. Envío y recepción concurrente de bundles para evitar deadlock en TCP
            coroutineScope {
                val sendJob = launch {
                    for (bundle in bundlesToSend) {
                        val bundleToSend = if (!bundle.isEncrypted && bundle.destEid != "broadcast") {
                            val encrypted = cryptoManager.encrypt(bundle.destEid, bundle.payload)
                            if (encrypted != null) bundle.copy(payload = encrypted, isEncrypted = true)
                            else bundle
                        } else bundle
                        BundleProtocol.writeBundleData(out, bundleToSend)
                        DTNLogger.onBundleSent(bundle.id, peerEid, bundle.payload.size)
                        sent++
                    }
                    BundleProtocol.writeBye(out)
                }

                socket.soTimeout = 30000
                while (true) {
                    val msg = BundleProtocol.readMessage(inp) ?: break
                    when (msg.first) {
                        BundleProtocol.MSG_BUNDLE_DATA -> {
                            val bundle = BundleProtocol.parseBundle(msg.second)
                            if (bundle != null) {
                                DTNLogger.onBundleReceived(bundle.id, peerEid, bundle.payload.size)
                                onBundleReceived(bundle, peerEid)
                                received++
                            }
                        }
                        BundleProtocol.MSG_BYE -> break
                        else -> {}
                    }
                }
                sendJob.join()
            }
            DTNLogger.onEpidemicSync(peerEid, sent, received)

        } catch (e: java.net.SocketTimeoutException) {
            DTNLogger.d(TAG, "Sesión completada con $peerEid: enviados=$sent recibidos=$received")
        } catch (e: Exception) {
            DTNLogger.e(TAG, "Error en sesión con $peerEid: ${e.message}")
        } finally {
            try { socket.close() } catch (_: Exception) {}
            if (peerEid.isNotEmpty()) DTNLogger.onContactLost(peerEid)
        }
        return Pair(sent, received)
    }

    fun disconnect() {
        manager.removeGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() = DTNLogger.i(TAG, "Grupo Wi-Fi Direct removido")
            override fun onFailure(r: Int) = DTNLogger.w(TAG, "Error removiendo grupo: $r")
        })
    }

    fun destroy() {
        try {
            context.unregisterReceiver(receiver)
        } catch (_: Exception) {}
        disconnect()
        serverJob?.cancel()
        retryJob?.cancel()
        scope.cancel()
    }
}
