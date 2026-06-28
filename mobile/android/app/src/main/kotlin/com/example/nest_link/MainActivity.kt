package com.example.nest_link

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import com.dtnmesh.app.model.DTNBundle
import com.dtnmesh.app.model.PayloadType
import com.dtnmesh.app.service.DTNService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Flutter ⇄ dtn-mesh bridge.
 *
 * MethodChannel "nestlink/mesh":
 *   start()                       -> starts + binds DTNService
 *   stop()                        -> unbinds + stops DTNService
 *   getLocalEid()                 -> this device's mesh EID (String)
 *   sendText(text, destEid?)      -> creates a TEXT bundle, returns its id
 *
 * EventChannel "nestlink/mesh/events":
 *   streams every received bundle as a Map (id, sourceEid, destEid, type, text, createdAt, hopCount)
 */
class MainActivity : FlutterActivity() {

    private val methodChannelName = "nestlink/mesh"
    private val eventChannelName = "nestlink/mesh/events"

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    private var dtnService: DTNService? = null
    private var bound = false
    private var eventSink: EventChannel.EventSink? = null
    private var collectJob: Job? = null
    private var familyCode: String = ""

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            val local = binder as? DTNService.LocalBinder ?: return
            dtnService = local.getService()
            dtnService?.familyCode = familyCode
            bound = true
            startCollecting()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            bound = false
            dtnService = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, methodChannelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    DTNService.start(this)
                    bindService(
                        Intent(this, DTNService::class.java),
                        connection,
                        Context.BIND_AUTO_CREATE
                    )
                    result.success(true)
                }

                "stop" -> {
                    if (bound) {
                        unbindService(connection)
                        bound = false
                    }
                    collectJob?.cancel()
                    collectJob = null
                    DTNService.stop(this)
                    dtnService = null
                    result.success(true)
                }

                "setFamilyCode" -> {
                    familyCode = call.argument<String>("code") ?: ""
                    dtnService?.familyCode = familyCode
                    result.success(true)
                }

                "rescan" -> {
                    dtnService?.rescan()
                    result.success(true)
                }

                "getMeshStatus" -> {
                    result.success(dtnService?.meshStatus() ?: emptyMap<String, Any>())
                }

                "getLocalEid" -> {
                    val eid = dtnService?.localEid ?: readPersistedEid()
                    if (eid != null) result.success(eid)
                    else result.error("NOT_READY", "Mesh service not bound yet", null)
                }

                "sendText" -> {
                    val text = call.argument<String>("text").orEmpty()
                    val dest = call.argument<String>("destEid") ?: "broadcast"
                    val svc = dtnService
                    if (svc == null) {
                        result.error("NOT_READY", "Mesh service not bound yet", null)
                    } else {
                        scope.launch {
                            val bundle = withContext(Dispatchers.IO) {
                                svc.bundleManager.createTextBundle(text, dest)
                            }
                            result.success(bundle.id)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, eventChannelName).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    startCollecting()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    collectJob?.cancel()
                    collectJob = null
                }
            }
        )
    }

    /** Starts forwarding received bundles to Flutter once both the sink and the service are ready. */
    private fun startCollecting() {
        val svc = dtnService ?: return
        val sink = eventSink ?: return
        if (collectJob != null) return
        collectJob = scope.launch {
            svc.receivedBundles.collect { bundle ->
                sink.success(bundleToMap(bundle))
            }
        }
    }

    private fun bundleToMap(b: DTNBundle): Map<String, Any?> = mapOf(
        "id" to b.id,
        "sourceEid" to b.sourceEid,
        "destEid" to b.destEid,
        "type" to b.payloadType.name,
        "text" to if (b.payloadType == PayloadType.TEXT) String(b.payload, Charsets.UTF_8) else null,
        "createdAt" to b.createdAt,
        "hopCount" to b.hopCount
    )

    /** Falls back to the EID the engine persisted on first run, so the UI can show it pre-bind. */
    private fun readPersistedEid(): String? =
        getSharedPreferences("dtn_prefs", Context.MODE_PRIVATE)
            .getString(DTNService.PREF_EID, null)

    override fun onDestroy() {
        collectJob?.cancel()
        if (bound) {
            unbindService(connection)
            bound = false
        }
        super.onDestroy()
    }
}
