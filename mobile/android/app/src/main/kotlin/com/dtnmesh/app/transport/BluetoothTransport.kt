package com.dtnmesh.app.transport

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
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
import java.util.UUID

@SuppressLint("MissingPermission")
class BluetoothTransport(
    private val context: Context,
    private val localEid: String,
    private val bundleManager: BundleManager,
    private val prophetRouter: ProphetRouter,
    private val cryptoManager: CryptoManager,
    private val onBundleReceived: suspend (DTNBundle, String) -> Unit
) {
    private val TAG = "Bluetooth"
    private val SERVICE_UUID = UUID.fromString("12345678-1234-5678-1234-56789abcdef0")
    private val SERVICE_NAME = "DTNMesh"

    private val btManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val btAdapter: BluetoothAdapter? = btManager.adapter

    private val _discoveredDevices = MutableStateFlow<List<BluetoothDevice>>(emptyList())
    val discoveredDevices: StateFlow<List<BluetoothDevice>> = _discoveredDevices

    private val _isAvailable = MutableStateFlow(btAdapter?.isEnabled == true)
    val isAvailable: StateFlow<Boolean> = _isAvailable

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var serverJob: Job? = null
    private val connectedDevices = mutableSetOf<String>()
    @Volatile private var discoveryScheduled = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                BluetoothDevice.ACTION_FOUND -> {
                    val device = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE) as? BluetoothDevice
                    }
                    device?.let {
                        val current = _discoveredDevices.value.toMutableList()
                        if (current.none { d -> d.address == it.address }) {
                            current.add(it)
                            _discoveredDevices.value = current
                            DTNLogger.d(TAG, "Dispositivo BT encontrado: ${it.name ?: it.address}")
                            // Solo intentar conectar si el dispositivo tiene nuestro servicio UUID
                            // (para no molestar dispositivos ajenos como TV, impresoras, etc.)
                            if (!connectedDevices.contains(it.address)) {
                                scope.launch { tryConnectIfDTN(it) }
                            }
                        }
                    }
                }
                BluetoothAdapter.ACTION_STATE_CHANGED -> {
                    val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, -1)
                    _isAvailable.value = state == BluetoothAdapter.STATE_ON
                    DTNLogger.onTransportEvent(TAG, "Estado Bluetooth: $state")
                }
                BluetoothAdapter.ACTION_DISCOVERY_FINISHED -> {
                    DTNLogger.d(TAG, "Descubrimiento BT terminado")
                    // Reiniciar descubrimiento periódicamente (guard evita cascade por cancelDiscovery)
                    if (!discoveryScheduled) {
                        discoveryScheduled = true
                        scope.launch {
                            delay(30_000)
                            discoveryScheduled = false
                            startDiscovery()
                        }
                    }
                }
            }
        }
    }

    fun initialize() {
        val filter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_FOUND)
            addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(BluetoothAdapter.ACTION_DISCOVERY_FINISHED)
        }
        context.registerReceiver(receiver, filter)
        DTNLogger.i(TAG, "Bluetooth inicializado. Disponible: ${btAdapter?.isEnabled}")
    }

    fun startServer() {
        if (btAdapter?.isEnabled != true) return
        serverJob = scope.launch {
            DTNLogger.i(TAG, "Servidor Bluetooth iniciado")
            var serverSocket: BluetoothServerSocket? = null
            try {
                serverSocket = btAdapter.listenUsingInsecureRfcommWithServiceRecord(SERVICE_NAME, SERVICE_UUID)
                while (isActive) {
                    val socket = serverSocket.accept() ?: continue
                    DTNLogger.onTransportEvent(TAG, "Conexión BT entrante de ${socket.remoteDevice.address}")
                    launch { handleSession(socket) }
                }
            } catch (e: Exception) {
                if (isActive) DTNLogger.e(TAG, "Error servidor BT: ${e.message}")
            } finally {
                try { serverSocket?.close() } catch (_: Exception) {}
            }
        }
    }

    fun startDiscovery() {
        if (btAdapter?.isEnabled != true) return
        discoveryScheduled = false
        btAdapter.cancelDiscovery()
        btAdapter.startDiscovery()
        DTNLogger.i(TAG, "Descubrimiento BT iniciado")
    }

    private suspend fun tryConnectIfDTN(device: BluetoothDevice) {
        // Verificar que el dispositivo tenga el UUID del servicio DTNMesh antes de conectar
        try {
            val uuids = device.uuids
            if (uuids != null && uuids.any { it.uuid == SERVICE_UUID }) {
                connectToDevice(device)
            } else if (uuids == null) {
                // Si no podemos verificar UUIDs (dispositivo no apareado), intentar igual
                connectToDevice(device)
            }
            // Si tiene UUIDs pero ninguno es el nuestro, ignorar silenciosamente
        } catch (_: Exception) {
            connectToDevice(device) // en caso de error al leer UUIDs, intentar de todas formas
        }
    }

    private suspend fun connectToDevice(device: BluetoothDevice) {
        if (connectedDevices.contains(device.address)) return
        delay(2000)
        var socket: BluetoothSocket? = null
        try {
            btAdapter?.cancelDiscovery()
            socket = device.createInsecureRfcommSocketToServiceRecord(SERVICE_UUID)
            socket.connect()
            connectedDevices.add(device.address)
            DTNLogger.onTransportEvent(TAG, "Conectado a ${device.name ?: device.address}")
            handleSession(socket)
        } catch (e: Exception) {
            DTNLogger.w(TAG, "No se pudo conectar a ${device.address}: ${e.message}")
        } finally {
            connectedDevices.remove(device.address)
            try { socket?.close() } catch (_: Exception) {}
        }
    }

    private suspend fun prepareBundlesToSend(
        peerIds: List<String>,
        peerEid: String,
        peerVector: Map<String, Float>
    ): List<DTNBundle> {
        val candidates = bundleManager.getMissingBundles(peerIds)
        val toSend = candidates.filter { prophetRouter.shouldForward(it, peerEid, peerVector) }
        return toSend.flatMap { FragmentManager.maybeFragment(it) }
    }

    private suspend fun handleSession(socket: BluetoothSocket) {
        var peerEid = ""
        var sent = 0
        var received = 0
        try {
            val out = DataOutputStream(socket.outputStream)
            val inp = DataInputStream(socket.inputStream)

            // 1. HELLO
            BundleProtocol.writeHello(out, localEid)
            val msg1 = withTimeoutOrNull(5000) { BundleProtocol.readMessage(inp) } ?: return
            if (msg1.first == BundleProtocol.MSG_HELLO) {
                peerEid = BundleProtocol.parseEid(msg1.second)
                DTNLogger.onContactEstablished(peerEid, socket.remoteDevice.address)
            } else return

            // 2. KEY_EXCHANGE
            BundleProtocol.writeKeyExchange(out, cryptoManager.getPublicKeyBytes())
            val msg2 = withTimeoutOrNull(5000) { BundleProtocol.readMessage(inp) } ?: return
            if (msg2.first == BundleProtocol.MSG_KEY_EXCHANGE) {
                cryptoManager.processPeerPublicKey(peerEid, msg2.second)
            }

            // 3. PROPHET_VECTOR
            prophetRouter.onContact(peerEid)
            BundleProtocol.writeProphetVector(out, prophetRouter.getProbabilityVector())
            val msg3 = withTimeoutOrNull(5000) { BundleProtocol.readMessage(inp) } ?: return
            var peerVector = emptyMap<String, Float>()
            if (msg3.first == BundleProtocol.MSG_PROPHET_VECTOR) {
                peerVector = BundleProtocol.parseProphetVector(msg3.second)
                prophetRouter.updateTransitivity(peerEid, peerVector)
            }

            // 4. BUNDLE_LIST — el servidor espera al cliente primero
            val isInitiator = socket.remoteDevice.address > localEid // determinismo: mayor MAC = cliente
            val bundlesToSend: List<DTNBundle>
            if (isInitiator) {
                BundleProtocol.writeBundleList(out, bundleManager.getAllIds())
                val msg4 = withTimeoutOrNull(5000) { BundleProtocol.readMessage(inp) } ?: return
                bundlesToSend = if (msg4.first == BundleProtocol.MSG_BUNDLE_LIST) {
                    val peerIds = BundleProtocol.parseBundleList(msg4.second)
                    prepareBundlesToSend(peerIds, peerEid, peerVector)
                } else emptyList()
            } else {
                val msg4 = withTimeoutOrNull(5000) { BundleProtocol.readMessage(inp) } ?: return
                BundleProtocol.writeBundleList(out, bundleManager.getAllIds())
                bundlesToSend = if (msg4.first == BundleProtocol.MSG_BUNDLE_LIST) {
                    val peerIds = BundleProtocol.parseBundleList(msg4.second)
                    prepareBundlesToSend(peerIds, peerEid, peerVector)
                } else emptyList()
            }

            // 5. Envío y recepción concurrente (evita deadlock en RFCOMM)
            coroutineScope {
                val sendJob = launch {
                    for (bundle in bundlesToSend) {
                        val bundleToSend = if (!bundle.isEncrypted && bundle.destEid != "broadcast") {
                            val enc = cryptoManager.encrypt(bundle.destEid, bundle.payload)
                            if (enc != null) bundle.copy(payload = enc, isEncrypted = true) else bundle
                        } else bundle
                        BundleProtocol.writeBundleData(out, bundleToSend)
                        DTNLogger.onBundleSent(bundle.id, peerEid, bundle.payload.size)
                        sent++
                    }
                    BundleProtocol.writeBye(out)
                }
                while (true) {
                    val msg = withTimeoutOrNull(30000) { BundleProtocol.readMessage(inp) } ?: break
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

        } catch (e: Exception) {
            DTNLogger.e(TAG, "Error sesión BT $peerEid: ${e.message}")
        } finally {
            try { socket.close() } catch (_: Exception) {}
            if (peerEid.isNotEmpty()) DTNLogger.onContactLost(peerEid)
        }
    }

    fun destroy() {
        try { context.unregisterReceiver(receiver) } catch (_: Exception) {}
        btAdapter?.cancelDiscovery()
        serverJob?.cancel()
        scope.cancel()
    }
}
