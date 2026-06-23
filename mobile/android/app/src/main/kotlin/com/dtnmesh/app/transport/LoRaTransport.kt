package com.dtnmesh.app.transport

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import com.dtnmesh.app.dtn.BundleManager
import com.dtnmesh.app.dtn.DTNLogger
import com.dtnmesh.app.model.DTNBundle
import com.hoho.android.usbserial.driver.UsbSerialDriver
import com.hoho.android.usbserial.driver.UsbSerialPort
import com.hoho.android.usbserial.driver.UsbSerialProber
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream

/**
 * Transporte LoRa via USB OTG.
 *
 * Conecta con módulos LoRa (TTGO T-Beam, Heltec LoRa 32, etc.) usando
 * usb-serial-for-android. El módulo debe correr firmware compatible
 * (ver README para instrucciones de firmware).
 *
 * Chips USB-Serial soportados automáticamente:
 *  - CP2102/CP2104 (TTGO, Heltec)
 *  - CH340/CH341 (clones chinos)
 *  - FTDI FT232 (módulos de calidad)
 *
 * Protocolo serial sobre LoRa:
 *  [MAGIC:2][TYPE:1][LENGTH:4][PAYLOAD:N][CRC16:2]
 *
 * Rango típico: 2–15 km según antena, potencia y terreno.
 */
class LoRaTransport(
    private val context: Context,
    private val localEid: String,
    private val bundleManager: BundleManager,
    private val onBundleReceived: suspend (DTNBundle, String) -> Unit
) {
    private val TAG = "LoRa"
    private val ACTION_USB_PERMISSION = "com.dtnmesh.app.USB_PERMISSION"
    private val BAUD_RATE = 115200
    private val MAGIC = byteArrayOf(0xDA.toByte(), 0xE0.toByte())

    // Tipos de trama
    private val FRAME_HELLO: Byte = 0x01
    private val FRAME_BUNDLE: Byte = 0x02
    private val FRAME_ACK: Byte = 0x03
    private val FRAME_BUNDLE_LIST: Byte = 0x04

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val _isConnected = MutableStateFlow(false)
    val isConnected: StateFlow<Boolean> = _isConnected

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var port: UsbSerialPort? = null
    private var commJob: Job? = null

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> {
                    DTNLogger.i(TAG, "Dispositivo USB conectado")
                    scope.launch { detectAndConnect() }
                }
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    DTNLogger.i(TAG, "Dispositivo USB desconectado")
                    _isConnected.value = false
                    port?.close()
                    port = null
                    commJob?.cancel()
                }
                ACTION_USB_PERMISSION -> {
                    val device = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION") intent.getParcelableExtra(UsbManager.EXTRA_DEVICE) as? UsbDevice
                    }
                    if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                        device?.let { scope.launch { openDevice(it) } }
                    } else {
                        DTNLogger.w(TAG, "Permiso USB denegado para ${device?.deviceName}")
                    }
                }
            }
        }
    }

    fun initialize() {
        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(ACTION_USB_PERMISSION)
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(usbReceiver, filter)
        }
        DTNLogger.i(TAG, "Transporte LoRa USB inicializado")
        scope.launch { detectAndConnect() }
    }

    private suspend fun detectAndConnect() {
        val availableDrivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager)
        if (availableDrivers.isEmpty()) {
            DTNLogger.d(TAG, "Ningún módulo USB-Serial detectado")
            return
        }
        val driver = availableDrivers.first()
        val device = driver.device
        DTNLogger.i(TAG, "Módulo USB detectado: ${device.deviceName} (${device.vendorId}:${device.productId})")
        if (!usbManager.hasPermission(device)) {
            val permIntent = PendingIntent.getBroadcast(
                context, 0,
                Intent(ACTION_USB_PERMISSION),
                PendingIntent.FLAG_IMMUTABLE
            )
            usbManager.requestPermission(device, permIntent)
        } else {
            openDevice(device)
        }
    }

    private suspend fun openDevice(device: UsbDevice) {
        try {
            val drivers = UsbSerialProber.getDefaultProber().findAllDrivers(usbManager)
            val driver: UsbSerialDriver = drivers.firstOrNull { it.device.deviceId == device.deviceId } ?: return
            val connection = usbManager.openDevice(driver.device) ?: return
            val p = driver.ports.first()
            p.open(connection)
            p.setParameters(BAUD_RATE, 8, UsbSerialPort.STOPBITS_1, UsbSerialPort.PARITY_NONE)
            port = p
            _isConnected.value = true
            DTNLogger.onTransportEvent(TAG, "Puerto LoRa abierto a ${BAUD_RATE}bps")
            commJob = scope.launch { runCommunication(p) }
        } catch (e: Exception) {
            DTNLogger.e(TAG, "Error abriendo puerto USB: ${e.message}")
        }
    }

    private suspend fun runCommunication(p: UsbSerialPort) {
        // Enviar HELLO
        sendFrame(p, FRAME_HELLO, localEid.toByteArray())
        // Enviar bundle list
        val ids = bundleManager.getAllIds()
        val idsJson = com.google.gson.Gson().toJson(ids)
        sendFrame(p, FRAME_BUNDLE_LIST, idsJson.toByteArray())
        // Enviar bundles pendientes
        val pending = bundleManager.getPendingBundles()
        for (bundle in pending) {
            val out = ByteArrayOutputStream()
            val dout = DataOutputStream(out)
            BundleProtocol.writeBundleData(dout, bundle)
            sendFrame(p, FRAME_BUNDLE, out.toByteArray())
            DTNLogger.onBundleSent(bundle.id, "LoRa", bundle.payload.size)
        }
        // Leer entrada
        val buf = ByteArray(4096)
        val accumulator = ByteArrayOutputStream()
        while (isActive) {
            try {
                val read = p.read(buf, 500)
                if (read > 0) {
                    accumulator.write(buf, 0, read)
                    processAccumulated(accumulator)
                }
            } catch (e: Exception) {
                if (isActive) DTNLogger.e(TAG, "Error leyendo LoRa: ${e.message}")
                break
            }
        }
    }

    private suspend fun processAccumulated(acc: ByteArrayOutputStream) {
        val bytes = acc.toByteArray()
        // Buscar tramas completas: [MAGIC:2][TYPE:1][LEN:4][PAYLOAD:N][CRC:2]
        var offset = 0
        while (offset + 9 < bytes.size) {
            if (bytes[offset] != MAGIC[0] || bytes[offset + 1] != MAGIC[1]) { offset++; continue }
            val type = bytes[offset + 2]
            val len = ((bytes[offset + 3].toInt() and 0xFF) shl 24) or
                      ((bytes[offset + 4].toInt() and 0xFF) shl 16) or
                      ((bytes[offset + 5].toInt() and 0xFF) shl 8) or
                      (bytes[offset + 6].toInt() and 0xFF)
            if (offset + 7 + len + 2 > bytes.size) break // trama incompleta
            val payload = bytes.copyOfRange(offset + 7, offset + 7 + len)
            // TODO: verificar CRC16
            when (type) {
                FRAME_BUNDLE -> {
                    val din = DataInputStream(ByteArrayInputStream(payload))
                    val msg = BundleProtocol.readMessage(din)
                    if (msg?.first == BundleProtocol.MSG_BUNDLE_DATA) {
                        val bundle = BundleProtocol.parseBundle(msg.second)
                        if (bundle != null) {
                            DTNLogger.onBundleReceived(bundle.id, "LoRa", bundle.payload.size)
                            onBundleReceived(bundle, "LoRa-${bundle.sourceEid}")
                        }
                    }
                }
                FRAME_HELLO -> DTNLogger.i(TAG, "LoRa HELLO de: ${String(payload)}")
                else -> {}
            }
            offset += 7 + len + 2
        }
        // Limpiar bytes procesados
        acc.reset()
        if (offset < bytes.size) acc.write(bytes, offset, bytes.size - offset)
    }

    private fun sendFrame(p: UsbSerialPort, type: Byte, payload: ByteArray) {
        try {
            val frame = ByteArray(2 + 1 + 4 + payload.size + 2)
            frame[0] = MAGIC[0]; frame[1] = MAGIC[1]; frame[2] = type
            frame[3] = (payload.size shr 24).toByte()
            frame[4] = (payload.size shr 16).toByte()
            frame[5] = (payload.size shr 8).toByte()
            frame[6] = payload.size.toByte()
            payload.copyInto(frame, 7)
            val crc = crc16(payload)
            frame[7 + payload.size] = (crc shr 8).toByte()
            frame[7 + payload.size + 1] = crc.toByte()
            p.write(frame, 1000)
        } catch (e: Exception) {
            DTNLogger.e(TAG, "Error enviando trama LoRa: ${e.message}")
        }
    }

    private fun crc16(data: ByteArray): Int {
        var crc = 0xFFFF
        for (b in data) {
            crc = crc xor (b.toInt() and 0xFF)
            repeat(8) { crc = if (crc and 1 != 0) (crc shr 1) xor 0xA001 else crc shr 1 }
        }
        return crc and 0xFFFF
    }

    private val isActive get() = commJob?.isActive == true

    fun destroy() {
        try { context.unregisterReceiver(usbReceiver) } catch (_: Exception) {}
        commJob?.cancel()
        port?.close()
        scope.cancel()
    }
}

// Extensión para evitar conflicto de nombre con Byte hex literal
private val Int.toByte get() = this.toByte()
