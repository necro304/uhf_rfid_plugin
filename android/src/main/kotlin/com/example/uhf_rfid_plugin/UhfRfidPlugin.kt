package com.example.uhf_rfid_plugin

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import com.handheld.uhfr.UHFRManager
import com.handheld.uhfr.Reader as HandheldReader
import com.uhf.api.cls.Reader
import com.uhf.api.cls.Reader.READER_ERR
import com.uhf.api.cls.Reader.Region_Conf
import com.uhf.api.cls.Reader.Lock_Obj
import com.uhf.api.cls.Reader.Lock_Type
import com.uhf.api.cls.Reader.TAGINFO

class UhfRfidPlugin: FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler, ActivityAware {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var buttonEventChannel: EventChannel
    private lateinit var barcodeEventChannel: EventChannel
    private lateinit var context: Context

    private var uhfManager: UHFRManager? = null
    private var eventSink: EventChannel.EventSink? = null
    private var buttonEventSink: EventChannel.EventSink? = null
    private var barcodeEventSink: EventChannel.EventSink? = null
    private var isReading = false
    private val mainHandler = Handler(Looper.getMainLooper())

    // Activity and button handling
    private var activity: Activity? = null
    private var keyReceiver: BroadcastReceiver? = null
    private var triggerButtonEnabled = true

    // Barcode scanner
    private var barcodeReceiver: BroadcastReceiver? = null
    private var isBarcodeInitialized = false

    companion object {
        private const val TAG = "UhfRfidPlugin"
        const val METHOD_CHANNEL = "com.example.uhf_rfid_plugin/methods"
        const val EVENT_CHANNEL = "com.example.uhf_rfid_plugin/tags"
        const val BUTTON_EVENT_CHANNEL = "com.example.uhf_rfid_plugin/button"
        const val BARCODE_EVENT_CHANNEL = "com.example.uhf_rfid_plugin/barcode"

        // Key codes for physical trigger buttons
        private val TRIGGER_KEY_CODES = listOf(
            KeyEvent.KEYCODE_F3,   // C510x
            KeyEvent.KEYCODE_F4,   // 6100
            KeyEvent.KEYCODE_F7,   // H3100
            134,                   // PDA scan key 1
            137                    // PDA scan key 2
        )

        // Barcode scanner actions
        private const val ACTION_BARCODE_INIT = "com.rfid.SCAN_INIT"
        private const val ACTION_BARCODE_SCAN = "com.rfid.SCAN_CMD"
        private const val ACTION_BARCODE_STOP = "com.rfid.STOP_SCAN"
        private const val ACTION_BARCODE_CLOSE = "com.rfid.CLOSE_SCAN"
        private const val ACTION_BARCODE_SET_MODE = "com.rfid.SET_SCAN_MODE"
        private const val ACTION_BARCODE_SET_TIME = "com.rfid.SCAN_TIME"
        private const val ACTION_BARCODE_RESULT = "com.rfid.SCAN"
    }

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)

        // Button event channel for physical trigger button
        buttonEventChannel = EventChannel(binding.binaryMessenger, BUTTON_EVENT_CHANNEL)
        buttonEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                buttonEventSink = events
            }
            override fun onCancel(arguments: Any?) {
                buttonEventSink = null
            }
        })

        // Barcode event channel for barcode scanner results
        barcodeEventChannel = EventChannel(binding.binaryMessenger, BARCODE_EVENT_CHANNEL)
        barcodeEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                barcodeEventSink = events
            }
            override fun onCancel(arguments: Any?) {
                barcodeEventSink = null
            }
        })
    }

    // ============ ActivityAware Implementation ============

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        registerKeyReceiver()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        unregisterKeyReceiver()
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        registerKeyReceiver()
    }

    override fun onDetachedFromActivity() {
        unregisterKeyReceiver()
        activity = null
    }

    // ============ Physical Button Handling ============

    private fun registerKeyReceiver() {
        if (keyReceiver != null) return

        keyReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (!triggerButtonEnabled) return

                val keyCode = intent?.getIntExtra("keyCode", 0)
                    ?: intent?.getIntExtra("keycode", 0)
                    ?: 0
                val keyDown = intent?.getBooleanExtra("keydown", false) ?: false

                Log.d(TAG, "KeyReceiver: keyCode=$keyCode, keyDown=$keyDown")

                if (keyCode in TRIGGER_KEY_CODES) {
                    // On key down, just send the event
                    if (keyDown) {
                        mainHandler.post {
                            buttonEventSink?.success(mapOf(
                                "keyCode" to keyCode,
                                "action" to "down",
                                "isReading" to isReading
                            ))
                        }
                    } else {
                        // On key up, toggle first then send event with NEW state
                        mainHandler.post {
                            toggleInventory()
                            // Send event AFTER toggle with the new isReading state
                            buttonEventSink?.success(mapOf(
                                "keyCode" to keyCode,
                                "action" to "up",
                                "isReading" to isReading
                            ))
                        }
                    }
                }
            }
        }

        val filter = IntentFilter().apply {
            addAction("android.rfid.FUN_KEY")
            addAction("android.intent.action.FUN_KEY")
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity?.registerReceiver(keyReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                activity?.registerReceiver(keyReceiver, filter)
            }
            Log.d(TAG, "KeyReceiver registered successfully")
            disableScanKeys()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register KeyReceiver: ${e.message}")
        }
    }

    private fun unregisterKeyReceiver() {
        keyReceiver?.let {
            try {
                activity?.unregisterReceiver(it)
                Log.d(TAG, "KeyReceiver unregistered")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to unregister KeyReceiver: ${e.message}")
            }
        }
        keyReceiver = null
        enableScanKeys()
    }

    private fun disableScanKeys() {
        if (Build.VERSION.SDK_INT > Build.VERSION_CODES.N) {
            try {
                val intent = Intent("com.rfid.KEY_SET")
                intent.putExtra("keyValueArray", arrayOf("134", "137"))
                intent.putExtra("134", false)
                intent.putExtra("137", false)
                context.sendBroadcast(intent)
                Log.d(TAG, "Scan keys disabled")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to disable scan keys: ${e.message}")
            }
        }
    }

    private fun enableScanKeys() {
        if (Build.VERSION.SDK_INT > Build.VERSION_CODES.N) {
            try {
                val intent = Intent("com.rfid.KEY_SET")
                intent.putExtra("keyValueArray", arrayOf("134", "137"))
                intent.putExtra("134", true)
                intent.putExtra("137", true)
                context.sendBroadcast(intent)
                Log.d(TAG, "Scan keys enabled")
            } catch (e: Exception) {
                Log.w(TAG, "Failed to enable scan keys: ${e.message}")
            }
        }
    }

    private fun toggleInventory() {
        if (uhfManager == null) {
            Log.w(TAG, "toggleInventory: Reader not initialized")
            return
        }

        if (!isReading) {
            Log.d(TAG, "toggleInventory: Starting inventory via physical button")
            uhfManager?.asyncStartReading()
            useRealTimeMode = true
            isReading = true
            startReadingLoop()
        } else {
            Log.d(TAG, "toggleInventory: Stopping inventory via physical button")
            stopReadingLoop()
            uhfManager?.asyncStopReading()
            useRealTimeMode = false
        }
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "init" -> initReader(result)
            "close" -> closeReader(result)
            "getHardwareVersion" -> getHardwareVersion(result)
            "startInventory" -> startInventory(result)
            "stopInventory" -> stopInventory(result)
            "inventoryOnce" -> inventoryOnce(call, result)
            "setPower" -> setPower(call, result)
            "getPower" -> getPower(result)
            "setRegion" -> setRegion(call, result)
            "getRegion" -> getRegion(result)
            "getTemperature" -> getTemperature(result)
            "readTagData" -> readTagData(call, result)
            "writeTagData" -> writeTagData(call, result)
            "writeTagEpc" -> writeTagEpc(call, result)
            "lockTag" -> lockTag(call, result)
            "killTag" -> killTag(call, result)
            "setInventoryFilter" -> setInventoryFilter(call, result)
            "cancelInventoryFilter" -> cancelInventoryFilter(result)
            "getFrequencyPoints" -> getFrequencyPoints(result)
            "setFrequencyPoints" -> setFrequencyPoints(call, result)
            // Physical button control
            "setTriggerButtonEnabled" -> setTriggerButtonEnabled(call, result)
            "isTriggerButtonEnabled" -> isTriggerButtonEnabled(result)
            "isReading" -> isReadingStatus(result)
            // Barcode scanner
            "initBarcode" -> initBarcodeScanner(result)
            "startBarcodeScan" -> startBarcodeScan(result)
            "stopBarcodeScan" -> stopBarcodeScan(result)
            "closeBarcode" -> closeBarcodeScanner(result)
            "setBarcodeScanMode" -> setBarcodeScanMode(call, result)
            "setBarcodeTimeout" -> setBarcodeTimeout(call, result)
            "isBarcodeInitialized" -> isBarcodeInitializedStatus(result)
            else -> result.notImplemented()
        }
    }

    // ============ Trigger Button Control ============

    private fun setTriggerButtonEnabled(call: MethodCall, result: Result) {
        triggerButtonEnabled = call.argument<Boolean>("enabled") ?: true
        Log.d(TAG, "Trigger button enabled: $triggerButtonEnabled")
        result.success(mapOf("success" to true, "enabled" to triggerButtonEnabled))
    }

    private fun isTriggerButtonEnabled(result: Result) {
        result.success(mapOf("enabled" to triggerButtonEnabled))
    }

    private fun isReadingStatus(result: Result) {
        result.success(mapOf("isReading" to isReading))
    }

    // ============ Inicialización ============

    private fun initReader(result: Result) {
        try {
            Log.d(TAG, "initReader: Starting initialization with SDK v3.6...")
            Log.d(TAG, "initReader: Device model: ${android.os.Build.MODEL}")
            Log.d(TAG, "initReader: Device manufacturer: ${android.os.Build.MANUFACTURER}")

            // SDK v3.6 handles device detection automatically
            uhfManager = UHFRManager.getInstance()
            Log.d(TAG, "initReader: getInstance() returned: ${uhfManager != null}")

            if (uhfManager == null) {
                Log.e(TAG, "initReader: getInstance() returned null")
                result.success(mapOf(
                    "success" to false,
                    "message" to "Failed to initialize UHF reader. Please check if UHF module is available."
                ))
                return
            }

            // Verify connection by trying to get hardware version
            val hardware = try {
                uhfManager?.getHardware()
            } catch (e: Exception) {
                Log.w(TAG, "initReader: getHardware() failed: ${e.message}")
                null
            }
            Log.d(TAG, "initReader: Hardware version: $hardware")

            // Try to set default power to verify reader is working
            val powerResult = try {
                uhfManager?.setPower(26, 26)
            } catch (e: Exception) {
                Log.w(TAG, "initReader: setPower() failed: ${e.message}")
                null
            }
            Log.d(TAG, "initReader: setPower result: $powerResult")

            val isConnected = powerResult == READER_ERR.MT_OK_ERR || hardware != null

            if (isConnected) {
                result.success(mapOf(
                    "success" to true,
                    "message" to "Reader initialized successfully",
                    "hardware" to (hardware ?: "unknown")
                ))
            } else {
                result.success(mapOf(
                    "success" to false,
                    "message" to "Reader instance created but not responding",
                    "hardware" to (hardware ?: "unknown")
                ))
            }
        } catch (e: Exception) {
            Log.e(TAG, "initReader: Exception: ${e.message}", e)
            result.error("INIT_ERROR", e.message, e.stackTraceToString())
        }
    }

    private fun closeReader(result: Result) {
        try {
            stopReadingLoop()
            uhfManager?.close()
            uhfManager = null
            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            result.error("CLOSE_ERROR", e.message, null)
        }
    }

    private fun getHardwareVersion(result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            // Get hardware info using getHardware method
            val hardware = manager.getHardware()
            result.success(hardware?.toString() ?: "Unknown")
        } catch (e: Exception) {
            result.error("VERSION_ERROR", e.message, null)
        }
    }

    // ============ Inventario ============

    private var useRealTimeMode = false  // Flag to track which mode we're using

    private fun startInventory(result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            Log.d(TAG, "startInventory: Starting continuous inventory...")

            // Start async reading mode first (required for tagInventoryRealTime)
            manager.asyncStartReading()
            useRealTimeMode = true

            isReading = true
            startReadingLoop()
            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            Log.e(TAG, "startInventory error: ${e.message}")
            result.error("START_ERROR", e.message, null)
        }
    }

    private fun stopInventory(result: Result) {
        try {
            Log.d(TAG, "stopInventory: Stopping inventory...")
            stopReadingLoop()
            uhfManager?.asyncStopReading()
            useRealTimeMode = false
            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            result.error("STOP_ERROR", e.message, null)
        }
    }

    private fun inventoryOnce(call: MethodCall, result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val timeout = call.argument<Int>("timeout") ?: 100
            Log.d(TAG, "inventoryOnce: timeout=$timeout")

            val tags = manager.tagInventoryByTimer(timeout.toShort())
            Log.d(TAG, "inventoryOnce: found ${tags?.size ?: 0} tags")

            val tagList = tags?.map { tag ->
                mapOf(
                    "epc" to bytesToHex(getEpcFromTagInfo(tag)),
                    "rssi" to (tag.RSSI ?: 0),
                    "count" to (tag.ReadCnt ?: 1)
                )
            } ?: emptyList()

            result.success(tagList)
        } catch (e: Exception) {
            Log.e(TAG, "inventoryOnce error: ${e.message}")
            result.error("INVENTORY_ERROR", e.message, null)
        }
    }

    private var readingThread: Thread? = null

    private fun startReadingLoop() {
        readingThread = Thread {
            Log.d(TAG, "startReadingLoop: Thread started, useRealTimeMode=$useRealTimeMode")
            while (isReading) {
                try {
                    val tags = if (useRealTimeMode) {
                        uhfManager?.tagInventoryRealTime()
                    } else {
                        uhfManager?.tagInventoryByTimer(50)
                    }

                    if (tags != null && tags.isNotEmpty()) {
                        Log.d(TAG, "startReadingLoop: Found ${tags.size} tags")
                        tags.forEach { tag ->
                            val tagData = mapOf(
                                "epc" to bytesToHex(getEpcFromTagInfo(tag)),
                                "rssi" to (tag.RSSI ?: 0),
                                "count" to (tag.ReadCnt ?: 1),
                                "antenna" to (tag.AntennaID?.toInt() ?: 0)
                            )
                            mainHandler.post {
                                eventSink?.success(tagData)
                            }
                        }
                    }
                    Thread.sleep(30)  // Reduced sleep for faster scanning
                } catch (e: InterruptedException) {
                    Log.d(TAG, "startReadingLoop: Thread interrupted")
                    break
                } catch (e: Exception) {
                    Log.e(TAG, "startReadingLoop error: ${e.message}")
                    mainHandler.post {
                        eventSink?.error("READ_ERROR", e.message, null)
                    }
                }
            }
            Log.d(TAG, "startReadingLoop: Thread ended")
        }
        readingThread?.start()
    }

    private fun stopReadingLoop() {
        isReading = false
        readingThread?.interrupt()
        readingThread = null
    }

    // ============ Configuración de Potencia ============

    private fun setPower(call: MethodCall, result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val readPower = call.argument<Int>("readPower") ?: 26
            val writePower = call.argument<Int>("writePower") ?: 26

            // Validar rango 5-33
            if (readPower !in 5..33 || writePower !in 5..33) {
                result.error("INVALID_POWER", "Power must be between 5 and 33", null)
                return
            }

            val err = manager.setPower(readPower, writePower)
            result.success(mapOf(
                "success" to (err == READER_ERR.MT_OK_ERR),
                "error" to err?.name
            ))
        } catch (e: Exception) {
            result.error("POWER_ERROR", e.message, null)
        }
    }

    private fun getPower(result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            // getPower() returns int[] where int[0]=readPower, int[1]=writePower
            val power = manager.getPower()
            if (power != null && power.size >= 2) {
                result.success(mapOf(
                    "readPower" to power[0],
                    "writePower" to power[1]
                ))
            } else {
                result.success(null)
            }
        } catch (e: Exception) {
            result.error("POWER_ERROR", e.message, null)
        }
    }

    // ============ Configuración de Región ============

    private fun setRegion(call: MethodCall, result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val regionStr = call.argument<String>("region") ?: "USA"
            val region = when (regionStr.uppercase()) {
                "CHN" -> Region_Conf.RG_PRC
                "USA" -> Region_Conf.RG_NA
                "EU" -> Region_Conf.RG_EU
                "KOREA" -> Region_Conf.RG_KR
                else -> Region_Conf.RG_NA
            }

            val err = manager.setRegion(region)
            result.success(mapOf(
                "success" to (err == READER_ERR.MT_OK_ERR),
                "error" to err?.name
            ))
        } catch (e: Exception) {
            result.error("REGION_ERROR", e.message, null)
        }
    }

    private fun getRegion(result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val region = manager.getRegion()
            val regionStr = when (region) {
                Region_Conf.RG_PRC -> "CHN"
                Region_Conf.RG_NA -> "USA"
                Region_Conf.RG_EU -> "EU"
                Region_Conf.RG_KR -> "KOREA"
                else -> "UNKNOWN"
            }
            result.success(regionStr)
        } catch (e: Exception) {
            result.error("REGION_ERROR", e.message, null)
        }
    }

    // ============ Lectura/Escritura de Tags ============

    private fun readTagData(call: MethodCall, result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val bank = call.argument<Int>("bank") ?: 1  // 0:RESERVED, 1:EPC, 2:TID, 3:USER
            val startAddr = call.argument<Int>("startAddr") ?: 0
            val length = call.argument<Int>("length") ?: 6
            val password = hexToBytes(call.argument<String>("password") ?: "00000000")
            val timeout = call.argument<Int>("timeout") ?: 1000

            val rdata = ByteArray(length * 2)  // length en words, rdata en bytes
            val err = manager.getTagData(bank, startAddr, length, rdata, password, timeout.toShort())

            if (err == READER_ERR.MT_OK_ERR) {
                result.success(mapOf(
                    "success" to true,
                    "data" to bytesToHex(rdata)
                ))
            } else {
                result.success(mapOf(
                    "success" to false,
                    "error" to err?.name
                ))
            }
        } catch (e: Exception) {
            result.error("READ_ERROR", e.message, null)
        }
    }

    private fun writeTagData(call: MethodCall, result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val bank = call.argument<Int>("bank") ?: 3  // USER bank por defecto
            val startAddr = call.argument<Int>("startAddr") ?: 0
            val dataHex = call.argument<String>("data") ?: ""
            val password = hexToBytes(call.argument<String>("password") ?: "00000000")
            val timeout = call.argument<Int>("timeout") ?: 1000

            val data = hexToBytes(dataHex)
            val dataLen = data.size / 2  // en words

            val bankChar = bank.toChar()

            val err = manager.writeTagData(bankChar, startAddr, data, dataLen, password, timeout.toShort())

            result.success(mapOf(
                "success" to (err == READER_ERR.MT_OK_ERR),
                "error" to err?.name
            ))
        } catch (e: Exception) {
            result.error("WRITE_ERROR", e.message, null)
        }
    }

    private fun writeTagEpc(call: MethodCall, result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val epcHex = call.argument<String>("epc") ?: ""
            val password = hexToBytes(call.argument<String>("password") ?: "00000000")
            val timeout = call.argument<Int>("timeout") ?: 1000

            val epcData = hexToBytes(epcHex)
            val err = manager.writeTagEPC(epcData, password, timeout.toShort())

            result.success(mapOf(
                "success" to (err == READER_ERR.MT_OK_ERR),
                "error" to err?.name
            ))
        } catch (e: Exception) {
            result.error("WRITE_EPC_ERROR", e.message, null)
        }
    }

    // ============ Lock/Kill Tags ============

    private fun lockTag(call: MethodCall, result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val lockObjStr = call.argument<String>("lockObject") ?: "EPC"
            val lockTypeStr = call.argument<String>("lockType") ?: "LOCK"
            val password = hexToBytes(call.argument<String>("password") ?: "00000000")
            val timeout = call.argument<Int>("timeout") ?: 1000

            val lockObj = when (lockObjStr.uppercase()) {
                "ACCESS_PASSWORD" -> Lock_Obj.LOCK_OBJECT_ACCESS_PASSWD
                "KILL_PASSWORD" -> Lock_Obj.LOCK_OBJECT_KILL_PASSWORD
                "EPC" -> Lock_Obj.LOCK_OBJECT_BANK1
                "TID" -> Lock_Obj.LOCK_OBJECT_BANK2
                "USER" -> Lock_Obj.LOCK_OBJECT_BANK3
                else -> Lock_Obj.LOCK_OBJECT_BANK1
            }

            // Determine lock type based on object and action
            val lockType = when (lockObjStr.uppercase()) {
                "KILL_PASSWORD" -> when (lockTypeStr.uppercase()) {
                    "UNLOCK" -> Lock_Type.KILL_PASSWORD_UNLOCK
                    "LOCK" -> Lock_Type.KILL_PASSWORD_LOCK
                    "PERMA_LOCK" -> Lock_Type.KILL_PASSWORD_PERM_LOCK
                    else -> Lock_Type.KILL_PASSWORD_LOCK
                }
                "ACCESS_PASSWORD" -> when (lockTypeStr.uppercase()) {
                    "UNLOCK" -> Lock_Type.ACCESS_PASSWD_UNLOCK
                    "LOCK" -> Lock_Type.ACCESS_PASSWD_LOCK
                    "PERMA_LOCK" -> Lock_Type.ACCESS_PASSWD_PERM_LOCK
                    else -> Lock_Type.ACCESS_PASSWD_LOCK
                }
                "EPC" -> when (lockTypeStr.uppercase()) {
                    "UNLOCK" -> Lock_Type.BANK1_UNLOCK
                    "LOCK" -> Lock_Type.BANK1_LOCK
                    "PERMA_LOCK" -> Lock_Type.BANK1_PERM_LOCK
                    else -> Lock_Type.BANK1_LOCK
                }
                "TID" -> when (lockTypeStr.uppercase()) {
                    "UNLOCK" -> Lock_Type.BANK2_UNLOCK
                    "LOCK" -> Lock_Type.BANK2_LOCK
                    "PERMA_LOCK" -> Lock_Type.BANK2_PERM_LOCK
                    else -> Lock_Type.BANK2_LOCK
                }
                "USER" -> when (lockTypeStr.uppercase()) {
                    "UNLOCK" -> Lock_Type.BANK3_UNLOCK
                    "LOCK" -> Lock_Type.BANK3_LOCK
                    "PERMA_LOCK" -> Lock_Type.BANK3_PERM_LOCK
                    else -> Lock_Type.BANK3_LOCK
                }
                else -> Lock_Type.BANK1_LOCK
            }

            val err = manager.lockTag(lockObj, lockType, password, timeout.toShort())

            result.success(mapOf(
                "success" to (err == READER_ERR.MT_OK_ERR),
                "error" to err?.name
            ))
        } catch (e: Exception) {
            result.error("LOCK_ERROR", e.message, null)
        }
    }

    private fun killTag(call: MethodCall, result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val killPassword = hexToBytes(call.argument<String>("killPassword") ?: "")
            val timeout = call.argument<Int>("timeout") ?: 1000

            // Validar que el password no sea 00000000
            if (killPassword.all { it == 0.toByte() }) {
                result.error("INVALID_PASSWORD", "Cannot kill tag with zero password", null)
                return
            }

            val err = manager.killTag(killPassword, timeout.toShort())

            result.success(mapOf(
                "success" to (err == READER_ERR.MT_OK_ERR),
                "error" to err?.name
            ))
        } catch (e: Exception) {
            result.error("KILL_ERROR", e.message, null)
        }
    }

    // ============ Filtros de Inventario ============

    private fun setInventoryFilter(call: MethodCall, result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val filterDataHex = call.argument<String>("filterData") ?: ""
            val bank = call.argument<Int>("bank") ?: 1  // 1:EPC, 2:TID, 3:USER
            val startAddr = call.argument<Int>("startAddr") ?: 0
            val matching = call.argument<Boolean>("matching") ?: true

            val filterData = hexToBytes(filterDataHex)
            val success = manager.setInventoryFilter(filterData, bank, startAddr, matching)

            result.success(mapOf("success" to success))
        } catch (e: Exception) {
            result.error("FILTER_ERROR", e.message, null)
        }
    }

    private fun cancelInventoryFilter(result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val success = manager.setCancleInventoryFilter()
            result.success(mapOf("success" to success))
        } catch (e: Exception) {
            result.error("FILTER_ERROR", e.message, null)
        }
    }

    // ============ Frecuencias ============

    private fun getFrequencyPoints(result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val points = manager.getFrequencyPoints()
            result.success(points?.toList())
        } catch (e: Exception) {
            result.error("FREQ_ERROR", e.message, null)
        }
    }

    private fun setFrequencyPoints(call: MethodCall, result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val pointsList = call.argument<List<Int>>("points") ?: emptyList()
            val pointsArray = pointsList.toIntArray()

            val err = manager.setFrequencyPoints(pointsArray)
            result.success(mapOf(
                "success" to (err == READER_ERR.MT_OK_ERR),
                "error" to err?.name
            ))
        } catch (e: Exception) {
            result.error("FREQ_ERROR", e.message, null)
        }
    }

    // ============ Barcode Scanner ============

    private fun initBarcodeScanner(result: Result) {
        try {
            Log.d(TAG, "initBarcodeScanner: Starting initialization...")

            // Register barcode receiver if not already registered
            if (barcodeReceiver == null) {
                barcodeReceiver = object : BroadcastReceiver() {
                    override fun onReceive(context: Context?, intent: Intent?) {
                        val data = intent?.getByteArrayExtra("data")
                        if (data != null) {
                            val barcode = String(data)
                            Log.d(TAG, "Barcode received: $barcode")
                            mainHandler.post {
                                barcodeEventSink?.success(mapOf(
                                    "barcode" to barcode,
                                    "rawData" to bytesToHex(data),
                                    "length" to data.size,
                                    "timestamp" to System.currentTimeMillis()
                                ))
                            }
                        }
                    }
                }

                val filter = IntentFilter(ACTION_BARCODE_RESULT)
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        activity?.registerReceiver(barcodeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        activity?.registerReceiver(barcodeReceiver, filter)
                    }
                    Log.d(TAG, "Barcode receiver registered")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to register barcode receiver: ${e.message}")
                }
            }

            // Send init broadcast
            val intent = Intent(ACTION_BARCODE_INIT)
            context.sendBroadcast(intent)

            // Set mode to BroadcastReceiver (mode 0)
            val modeIntent = Intent(ACTION_BARCODE_SET_MODE)
            modeIntent.putExtra("mode", 0)
            context.sendBroadcast(modeIntent)

            isBarcodeInitialized = true
            Log.d(TAG, "Barcode scanner initialized successfully")

            result.success(mapOf(
                "success" to true,
                "message" to "Barcode scanner initialized"
            ))
        } catch (e: Exception) {
            Log.e(TAG, "initBarcodeScanner error: ${e.message}")
            result.error("BARCODE_INIT_ERROR", e.message, null)
        }
    }

    private fun startBarcodeScan(result: Result) {
        try {
            if (!isBarcodeInitialized) {
                result.success(mapOf(
                    "success" to false,
                    "message" to "Barcode scanner not initialized"
                ))
                return
            }

            val intent = Intent(ACTION_BARCODE_SCAN)
            context.sendBroadcast(intent)
            Log.d(TAG, "Barcode scan started")

            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            Log.e(TAG, "startBarcodeScan error: ${e.message}")
            result.error("BARCODE_SCAN_ERROR", e.message, null)
        }
    }

    private fun stopBarcodeScan(result: Result) {
        try {
            val intent = Intent(ACTION_BARCODE_STOP)
            context.sendBroadcast(intent)
            Log.d(TAG, "Barcode scan stopped")

            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            Log.e(TAG, "stopBarcodeScan error: ${e.message}")
            result.error("BARCODE_STOP_ERROR", e.message, null)
        }
    }

    private fun closeBarcodeScanner(result: Result) {
        try {
            // Set mode back to focus input (mode 1) before closing
            val modeIntent = Intent(ACTION_BARCODE_SET_MODE)
            modeIntent.putExtra("mode", 1)
            context.sendBroadcast(modeIntent)

            // Close scanner service
            val intent = Intent(ACTION_BARCODE_CLOSE)
            context.sendBroadcast(intent)

            // Unregister receiver
            barcodeReceiver?.let {
                try {
                    activity?.unregisterReceiver(it)
                    Log.d(TAG, "Barcode receiver unregistered")
                } catch (e: Exception) {
                    Log.w(TAG, "Failed to unregister barcode receiver: ${e.message}")
                }
            }
            barcodeReceiver = null
            isBarcodeInitialized = false

            Log.d(TAG, "Barcode scanner closed")
            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            Log.e(TAG, "closeBarcodeScanner error: ${e.message}")
            result.error("BARCODE_CLOSE_ERROR", e.message, null)
        }
    }

    private fun setBarcodeScanMode(call: MethodCall, result: Result) {
        try {
            val mode = call.argument<Int>("mode") ?: 0
            // mode 0 = BroadcastReceiver mode, mode 1 = Focus input mode
            if (mode !in 0..1) {
                result.error("INVALID_MODE", "Mode must be 0 or 1", null)
                return
            }

            val intent = Intent(ACTION_BARCODE_SET_MODE)
            intent.putExtra("mode", mode)
            context.sendBroadcast(intent)

            Log.d(TAG, "Barcode scan mode set to: $mode")
            result.success(mapOf("success" to true, "mode" to mode))
        } catch (e: Exception) {
            Log.e(TAG, "setBarcodeScanMode error: ${e.message}")
            result.error("BARCODE_MODE_ERROR", e.message, null)
        }
    }

    private fun setBarcodeTimeout(call: MethodCall, result: Result) {
        try {
            val timeout = call.argument<Int>("timeout") ?: 5000
            // Valid values: 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000
            val validTimeouts = listOf(1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000)
            if (timeout !in validTimeouts) {
                result.error("INVALID_TIMEOUT", "Timeout must be one of: $validTimeouts", null)
                return
            }

            val intent = Intent(ACTION_BARCODE_SET_TIME)
            intent.putExtra("time", timeout.toString())
            context.sendBroadcast(intent)

            Log.d(TAG, "Barcode timeout set to: $timeout")
            result.success(mapOf("success" to true, "timeout" to timeout))
        } catch (e: Exception) {
            Log.e(TAG, "setBarcodeTimeout error: ${e.message}")
            result.error("BARCODE_TIMEOUT_ERROR", e.message, null)
        }
    }

    private fun isBarcodeInitializedStatus(result: Result) {
        result.success(mapOf("initialized" to isBarcodeInitialized))
    }

    // ============ Temperatura ============

    private fun getTemperature(result: Result) {
        try {
            val manager = uhfManager ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            // SDK v3.6 uses getYueheTagTemperature or getYilianTagTemperature
            // Try to get temperature from a tag
            try {
                val tempTags = manager.getYueheTagTemperature(null)
                if (tempTags != null && tempTags.isNotEmpty()) {
                    val firstTag = tempTags.first()
                    result.success(mapOf(
                        "temperature" to firstTag.Temperature,
                        "epc" to bytesToHex(firstTag.EpcId?.copyOf(firstTag.Epclen.toInt()) ?: ByteArray(0))
                    ))
                    return
                }
            } catch (e: Exception) {
                Log.w(TAG, "getYueheTagTemperature failed: ${e.message}")
            }

            // Fallback: try Yilian temperature tags
            try {
                val tempTags = manager.getYilianTagTemperature()
                if (tempTags != null && tempTags.isNotEmpty()) {
                    val firstTag = tempTags.first()
                    result.success(mapOf(
                        "temperature" to firstTag.Temperature,
                        "epc" to bytesToHex(firstTag.EpcId?.copyOf(firstTag.Epclen.toInt()) ?: ByteArray(0))
                    ))
                    return
                }
            } catch (e: Exception) {
                Log.w(TAG, "getYilianTagTemperature failed: ${e.message}")
            }

            result.success(mapOf("error" to "No temperature tags found"))
        } catch (e: Exception) {
            result.error("TEMP_ERROR", e.message, null)
        }
    }

    // ============ Event Channel ============

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        stopReadingLoop()
        unregisterKeyReceiver()

        // Close barcode scanner
        barcodeReceiver?.let {
            try {
                activity?.unregisterReceiver(it)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to unregister barcode receiver: ${e.message}")
            }
        }
        barcodeReceiver = null
        isBarcodeInitialized = false

        uhfManager?.close()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        buttonEventChannel.setStreamHandler(null)
        barcodeEventChannel.setStreamHandler(null)
    }

    // ============ Utilidades ============

    private fun getEpcFromTagInfo(tagInfo: TAGINFO): ByteArray {
        // Extract EPC bytes from TAGINFO
        // Epclen is Short, convert to Int for copyOf()
        val epcLen = (tagInfo.Epclen ?: 0).toInt()
        if (epcLen > 0 && tagInfo.EpcId != null) {
            return tagInfo.EpcId.copyOf(epcLen)
        }
        return ByteArray(0)
    }

    private fun bytesToHex(bytes: ByteArray?): String {
        if (bytes == null) return ""
        return bytes.joinToString("") { "%02X".format(it) }
    }

    private fun hexToBytes(hex: String): ByteArray {
        val cleanHex = hex.replace(" ", "").uppercase()
        if (cleanHex.isEmpty()) return ByteArray(0)

        return ByteArray(cleanHex.length / 2) { i ->
            cleanHex.substring(i * 2, i * 2 + 2).toInt(16).toByte()
        }
    }
}
