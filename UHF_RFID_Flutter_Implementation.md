# UHF RFID SDK - Implementación en Flutter

## Descripción General

Este documento describe cómo integrar el SDK UHF RFID R2000 (v2.5) en una aplicación Flutter utilizando Platform Channels para la comunicación entre Dart y el código nativo Android.

## Contenido del SDK

```
jar_so/
├── ModuleAPI_J.jar      # API principal del módulo hardware
├── uhfr_v1.9.jar        # Biblioteca UHF RFID Manager
├── jxl.jar              # Librería Excel (opcional, para exportar datos)
└── jniLibs/
    ├── arm64-v8a/       # Librerías nativas 64-bit
    ├── armeabi/         # Librerías nativas ARM legacy
    └── armeabi-v7a/     # Librerías nativas 32-bit
        ├── libModuleAPIJni.so
        ├── libSerialPort.so
        ├── libdevapi.so
        └── libirdaSerialPort.so
```

## Arquitectura de Integración

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App (Dart)                    │
│  ┌─────────────────────────────────────────────────┐    │
│  │              UhfRfidPlugin (Dart)                │    │
│  │         MethodChannel / EventChannel             │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                   Android Native                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │         UhfRfidPlugin.kt (Kotlin)                │    │
│  │              MethodCallHandler                   │    │
│  └─────────────────────────────────────────────────┘    │
│                           │                              │
│                           ▼                              │
│  ┌─────────────────────────────────────────────────┐    │
│  │              UHFRManager (SDK)                   │    │
│  │         uhfr_v1.9.jar + ModuleAPI_J.jar         │    │
│  └─────────────────────────────────────────────────┘    │
│                           │                              │
│                           ▼                              │
│  ┌─────────────────────────────────────────────────┐    │
│  │           Native Libraries (.so)                 │    │
│  │   libModuleAPIJni.so, libSerialPort.so, etc.    │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

---

## Paso 1: Crear el Plugin Flutter

### 1.1 Estructura del Proyecto

```bash
flutter create --template=plugin --platforms=android uhf_rfid_plugin
```

Estructura resultante:
```
uhf_rfid_plugin/
├── android/
│   └── src/main/
│       ├── kotlin/
│       │   └── com/example/uhf_rfid_plugin/
│       │       └── UhfRfidPlugin.kt
│       └── libs/                    # Agregar JARs aquí
├── lib/
│   └── uhf_rfid_plugin.dart
└── pubspec.yaml
```

---

## Paso 2: Configuración Android

### 2.1 Copiar Archivos del SDK

```bash
# Desde el directorio del plugin
mkdir -p android/src/main/libs
mkdir -p android/src/main/jniLibs

# Copiar JARs
cp /path/to/sdk/jar_so/ModuleAPI_J.jar android/src/main/libs/
cp /path/to/sdk/jar_so/uhfr_v1.9.jar android/src/main/libs/

# Copiar librerías nativas
cp -r /path/to/sdk/jar_so/jniLibs/* android/src/main/jniLibs/
```

### 2.2 Configurar build.gradle (android/build.gradle)

```groovy
group 'com.example.uhf_rfid_plugin'
version '1.0'

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath 'com.android.tools.build:gradle:7.3.0'
        classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:1.7.10"
    }
}

rootProject.allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

apply plugin: 'com.android.library'
apply plugin: 'kotlin-android'

android {
    compileSdkVersion 33

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_1_8
        targetCompatibility JavaVersion.VERSION_1_8
    }

    kotlinOptions {
        jvmTarget = '1.8'
    }

    sourceSets {
        main {
            jniLibs.srcDirs = ['src/main/jniLibs']
        }
    }

    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 33

        ndk {
            abiFilters 'armeabi-v7a', 'arm64-v8a'
        }
    }
}

dependencies {
    implementation "org.jetbrains.kotlin:kotlin-stdlib-jdk7:1.7.10"
    implementation files('src/main/libs/ModuleAPI_J.jar')
    implementation files('src/main/libs/uhfr_v1.9.jar')
}
```

### 2.3 AndroidManifest.xml

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.uhf_rfid_plugin">

    <!-- Permisos requeridos para comunicación serial/hardware -->
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>

    <!-- Característica USB Host (si aplica) -->
    <uses-feature android:name="android.hardware.usb.host" android:required="false"/>
</manifest>
```

---

## Paso 3: Código Nativo Android (Kotlin)

### 3.1 UhfRfidPlugin.kt

```kotlin
package com.example.uhf_rfid_plugin

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import com.uhf.api.cls.Reader
import com.uhf.api.cls.Reader.READER_ERR
import com.android.hdhe.uhf.reader.UhfReader

class UhfRfidPlugin: FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context

    private var uhfReader: UhfReader? = null
    private var eventSink: EventChannel.EventSink? = null
    private var isReading = false
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        const val METHOD_CHANNEL = "com.example.uhf_rfid_plugin/methods"
        const val EVENT_CHANNEL = "com.example.uhf_rfid_plugin/tags"
    }

    override fun onAttachedToEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
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
            else -> result.notImplemented()
        }
    }

    // ============ Inicialización ============

    private fun initReader(result: Result) {
        try {
            uhfReader = UhfReader.getInstance()
            if (uhfReader != null) {
                result.success(mapOf("success" to true, "message" to "Reader initialized"))
            } else {
                result.success(mapOf("success" to false, "message" to "Failed to initialize reader"))
            }
        } catch (e: Exception) {
            result.error("INIT_ERROR", e.message, null)
        }
    }

    private fun closeReader(result: Result) {
        try {
            stopReadingLoop()
            val success = uhfReader?.close() ?: false
            uhfReader = null
            result.success(mapOf("success" to success))
        } catch (e: Exception) {
            result.error("CLOSE_ERROR", e.message, null)
        }
    }

    private fun getHardwareVersion(result: Result) {
        try {
            val version = uhfReader?.hardwareVersion
            result.success(version)
        } catch (e: Exception) {
            result.error("VERSION_ERROR", e.message, null)
        }
    }

    // ============ Inventario ============

    private fun startInventory(result: Result) {
        try {
            val reader = uhfReader ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val err = reader.asyncStartReading()
            if (err == READER_ERR.MT_OK_ERR) {
                isReading = true
                startReadingLoop()
                result.success(mapOf("success" to true))
            } else {
                result.success(mapOf("success" to false, "error" to err.name))
            }
        } catch (e: Exception) {
            result.error("START_ERROR", e.message, null)
        }
    }

    private fun stopInventory(result: Result) {
        try {
            stopReadingLoop()
            val reader = uhfReader ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val err = reader.asyncStopReading()
            result.success(mapOf(
                "success" to (err == READER_ERR.MT_OK_ERR),
                "error" to err.name
            ))
        } catch (e: Exception) {
            result.error("STOP_ERROR", e.message, null)
        }
    }

    private fun inventoryOnce(call: MethodCall, result: Result) {
        try {
            val reader = uhfReader ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val timeout = call.argument<Int>("timeout") ?: 100
            val tags = reader.tagInventoryByTimer(timeout.toShort())

            val tagList = tags?.map { tag ->
                mapOf(
                    "epc" to bytesToHex(tag.epcData),
                    "rssi" to tag.rssi,
                    "count" to tag.count
                )
            } ?: emptyList()

            result.success(tagList)
        } catch (e: Exception) {
            result.error("INVENTORY_ERROR", e.message, null)
        }
    }

    private var readingThread: Thread? = null

    private fun startReadingLoop() {
        readingThread = Thread {
            while (isReading) {
                try {
                    val tags = uhfReader?.tagInventoryRealTime()
                    tags?.forEach { tag ->
                        val tagData = mapOf(
                            "epc" to bytesToHex(tag.epcData),
                            "rssi" to tag.rssi,
                            "count" to tag.count,
                            "antenna" to tag.antenna
                        )
                        mainHandler.post {
                            eventSink?.success(tagData)
                        }
                    }
                    Thread.sleep(50)
                } catch (e: InterruptedException) {
                    break
                } catch (e: Exception) {
                    mainHandler.post {
                        eventSink?.error("READ_ERROR", e.message, null)
                    }
                }
            }
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
            val reader = uhfReader ?: run {
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

            val err = reader.setPower(readPower, writePower)
            result.success(mapOf(
                "success" to (err == READER_ERR.MT_OK_ERR),
                "error" to err.name
            ))
        } catch (e: Exception) {
            result.error("POWER_ERROR", e.message, null)
        }
    }

    private fun getPower(result: Result) {
        try {
            val reader = uhfReader ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val power = reader.power
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
            val reader = uhfReader ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val regionStr = call.argument<String>("region") ?: "USA"
            val region = when (regionStr.uppercase()) {
                "CHN" -> Reader.Region_Conf.RG_CHN
                "USA" -> Reader.Region_Conf.RG_NA
                "EU" -> Reader.Region_Conf.RG_EU
                "KOREA" -> Reader.Region_Conf.RG_KOR
                else -> Reader.Region_Conf.RG_NA
            }

            val err = reader.setRegion(region)
            result.success(mapOf(
                "success" to (err == READER_ERR.MT_OK_ERR),
                "error" to err.name
            ))
        } catch (e: Exception) {
            result.error("REGION_ERROR", e.message, null)
        }
    }

    private fun getRegion(result: Result) {
        try {
            val reader = uhfReader ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val region = reader.region
            val regionStr = when (region) {
                Reader.Region_Conf.RG_CHN -> "CHN"
                Reader.Region_Conf.RG_NA -> "USA"
                Reader.Region_Conf.RG_EU -> "EU"
                Reader.Region_Conf.RG_KOR -> "KOREA"
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
            val reader = uhfReader ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val bank = call.argument<Int>("bank") ?: 1  // 0:RESERVED, 1:EPC, 2:TID, 3:USER
            val startAddr = call.argument<Int>("startAddr") ?: 0
            val length = call.argument<Int>("length") ?: 6
            val password = hexToBytes(call.argument<String>("password") ?: "00000000")
            val timeout = call.argument<Int>("timeout") ?: 1000

            val rdata = ByteArray(length * 2)  // length en words, rdata en bytes
            val err = reader.getTagData(bank, startAddr, length, rdata, password, timeout.toShort())

            if (err == READER_ERR.MT_OK_ERR) {
                result.success(mapOf(
                    "success" to true,
                    "data" to bytesToHex(rdata)
                ))
            } else {
                result.success(mapOf(
                    "success" to false,
                    "error" to err.name
                ))
            }
        } catch (e: Exception) {
            result.error("READ_ERROR", e.message, null)
        }
    }

    private fun writeTagData(call: MethodCall, result: Result) {
        try {
            val reader = uhfReader ?: run {
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

            val err = reader.writeTagData(bank.toChar(), startAddr, data, dataLen, password, timeout.toShort())

            result.success(mapOf(
                "success" to (err == READER_ERR.MT_OK_ERR),
                "error" to err.name
            ))
        } catch (e: Exception) {
            result.error("WRITE_ERROR", e.message, null)
        }
    }

    private fun writeTagEpc(call: MethodCall, result: Result) {
        try {
            val reader = uhfReader ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val epcHex = call.argument<String>("epc") ?: ""
            val password = hexToBytes(call.argument<String>("password") ?: "00000000")
            val timeout = call.argument<Int>("timeout") ?: 1000

            val epcData = hexToBytes(epcHex)
            val err = reader.writeTagEPC(epcData, password, timeout.toShort())

            result.success(mapOf(
                "success" to (err == READER_ERR.MT_OK_ERR),
                "error" to err.name
            ))
        } catch (e: Exception) {
            result.error("WRITE_EPC_ERROR", e.message, null)
        }
    }

    // ============ Lock/Kill Tags ============

    private fun lockTag(call: MethodCall, result: Result) {
        try {
            val reader = uhfReader ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val lockObjStr = call.argument<String>("lockObject") ?: "EPC"
            val lockTypeStr = call.argument<String>("lockType") ?: "LOCK"
            val password = hexToBytes(call.argument<String>("password") ?: "00000000")
            val timeout = call.argument<Int>("timeout") ?: 1000

            val lockObj = when (lockObjStr.uppercase()) {
                "ACCESS_PASSWORD" -> Reader.Lock_Obj.LOCK_OBJECT_ACCESS_PASSWD
                "KILL_PASSWORD" -> Reader.Lock_Obj.LOCK_OBJECT_KILL_PASSWD
                "EPC" -> Reader.Lock_Obj.LOCK_OBJECT_BANK1
                "TID" -> Reader.Lock_Obj.LOCK_OBJECT_BANK2
                "USER" -> Reader.Lock_Obj.LOCK_OBJECT_BANK3
                else -> Reader.Lock_Obj.LOCK_OBJECT_BANK1
            }

            val lockType = when (lockTypeStr.uppercase()) {
                "UNLOCK" -> Reader.Lock_Type.UNLOCK
                "LOCK" -> Reader.Lock_Type.LOCK
                "PERMA_LOCK" -> Reader.Lock_Type.PERMA_LOCK
                "PERMA_UNLOCK" -> Reader.Lock_Type.PERMA_UNLOCK
                else -> Reader.Lock_Type.LOCK
            }

            val err = reader.lockTag(lockObj, lockType, password, timeout.toShort())

            result.success(mapOf(
                "success" to (err == READER_ERR.MT_OK_ERR),
                "error" to err.name
            ))
        } catch (e: Exception) {
            result.error("LOCK_ERROR", e.message, null)
        }
    }

    private fun killTag(call: MethodCall, result: Result) {
        try {
            val reader = uhfReader ?: run {
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

            val err = reader.killTag(killPassword, timeout.toShort())

            result.success(mapOf(
                "success" to (err == READER_ERR.MT_OK_ERR),
                "error" to err.name
            ))
        } catch (e: Exception) {
            result.error("KILL_ERROR", e.message, null)
        }
    }

    // ============ Filtros de Inventario ============

    private fun setInventoryFilter(call: MethodCall, result: Result) {
        try {
            val reader = uhfReader ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val filterDataHex = call.argument<String>("filterData") ?: ""
            val bank = call.argument<Int>("bank") ?: 1  // 1:EPC, 2:TID, 3:USER
            val startAddr = call.argument<Int>("startAddr") ?: 0
            val matching = call.argument<Boolean>("matching") ?: true

            val filterData = hexToBytes(filterDataHex)
            val success = reader.setInventoryFilter(filterData, bank, startAddr, matching)

            result.success(mapOf("success" to success))
        } catch (e: Exception) {
            result.error("FILTER_ERROR", e.message, null)
        }
    }

    private fun cancelInventoryFilter(result: Result) {
        try {
            val reader = uhfReader ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val success = reader.setCancleInventoryFilter()
            result.success(mapOf("success" to success))
        } catch (e: Exception) {
            result.error("FILTER_ERROR", e.message, null)
        }
    }

    // ============ Frecuencias ============

    private fun getFrequencyPoints(result: Result) {
        try {
            val reader = uhfReader ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val points = reader.frequencyPoints
            result.success(points?.toList())
        } catch (e: Exception) {
            result.error("FREQ_ERROR", e.message, null)
        }
    }

    private fun setFrequencyPoints(call: MethodCall, result: Result) {
        try {
            val reader = uhfReader ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val pointsList = call.argument<List<Int>>("points") ?: emptyList()
            val pointsArray = pointsList.toIntArray()

            val err = reader.setFrequencyPoints(pointsArray)
            result.success(mapOf(
                "success" to (err == READER_ERR.MT_OK_ERR),
                "error" to err.name
            ))
        } catch (e: Exception) {
            result.error("FREQ_ERROR", e.message, null)
        }
    }

    // ============ Temperatura ============

    private fun getTemperature(result: Result) {
        try {
            val reader = uhfReader ?: run {
                result.error("NOT_INITIALIZED", "Reader not initialized", null)
                return
            }

            val temp = reader.temperature
            if (temp > 0) {
                result.success(mapOf("temperature" to temp))
            } else {
                result.success(mapOf("error" to "Failed to read temperature"))
            }
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
        uhfReader?.close()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    // ============ Utilidades ============

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
```

---

## Paso 4: Código Dart (Flutter)

### 4.1 lib/uhf_rfid_plugin.dart

```dart
import 'dart:async';
import 'package:flutter/services.dart';

/// Modelo de datos para un tag RFID
class RfidTag {
  final String epc;
  final int rssi;
  final int count;
  final int? antenna;

  RfidTag({
    required this.epc,
    required this.rssi,
    required this.count,
    this.antenna,
  });

  factory RfidTag.fromMap(Map<dynamic, dynamic> map) {
    return RfidTag(
      epc: map['epc'] as String? ?? '',
      rssi: map['rssi'] as int? ?? 0,
      count: map['count'] as int? ?? 0,
      antenna: map['antenna'] as int?,
    );
  }

  @override
  String toString() => 'RfidTag(epc: $epc, rssi: $rssi, count: $count)';
}

/// Enumeración de bancos de memoria del tag
enum MemoryBank {
  reserved(0),
  epc(1),
  tid(2),
  user(3);

  final int value;
  const MemoryBank(this.value);
}

/// Enumeración de regiones de frecuencia
enum FrequencyRegion {
  china('CHN'),
  usa('USA'),
  europe('EU'),
  korea('KOREA');

  final String value;
  const FrequencyRegion(this.value);
}

/// Enumeración de objetos bloqueables
enum LockObject {
  accessPassword('ACCESS_PASSWORD'),
  killPassword('KILL_PASSWORD'),
  epc('EPC'),
  tid('TID'),
  user('USER');

  final String value;
  const LockObject(this.value);
}

/// Enumeración de tipos de bloqueo
enum LockType {
  unlock('UNLOCK'),
  lock('LOCK'),
  permaLock('PERMA_LOCK'),
  permaUnlock('PERMA_UNLOCK');

  final String value;
  const LockType(this.value);
}

/// Plugin principal para UHF RFID
class UhfRfidPlugin {
  static const MethodChannel _methodChannel =
      MethodChannel('com.example.uhf_rfid_plugin/methods');

  static const EventChannel _eventChannel =
      EventChannel('com.example.uhf_rfid_plugin/tags');

  static Stream<RfidTag>? _tagStream;

  /// Stream de tags leídos en tiempo real
  static Stream<RfidTag> get tagStream {
    _tagStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => RfidTag.fromMap(event as Map<dynamic, dynamic>));
    return _tagStream!;
  }

  // ============ Inicialización ============

  /// Inicializa el lector UHF
  /// Retorna true si se inicializó correctamente
  static Future<bool> init() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('init');
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to initialize: ${e.message}');
    }
  }

  /// Cierra la conexión con el lector
  static Future<bool> close() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('close');
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to close: ${e.message}');
    }
  }

  /// Obtiene la versión del hardware
  static Future<String?> getHardwareVersion() async {
    try {
      return await _methodChannel.invokeMethod<String>('getHardwareVersion');
    } on PlatformException catch (e) {
      throw UhfException('Failed to get hardware version: ${e.message}');
    }
  }

  // ============ Inventario ============

  /// Inicia el inventario continuo de tags
  /// Los tags se reciben a través de [tagStream]
  static Future<bool> startInventory() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('startInventory');
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to start inventory: ${e.message}');
    }
  }

  /// Detiene el inventario continuo
  static Future<bool> stopInventory() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('stopInventory');
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to stop inventory: ${e.message}');
    }
  }

  /// Realiza un inventario único por tiempo
  /// [timeout] tiempo en milisegundos (default: 100ms)
  static Future<List<RfidTag>> inventoryOnce({int timeout = 100}) async {
    try {
      final result = await _methodChannel.invokeMethod<List>(
        'inventoryOnce',
        {'timeout': timeout},
      );
      return result
              ?.map((e) => RfidTag.fromMap(e as Map<dynamic, dynamic>))
              .toList() ??
          [];
    } on PlatformException catch (e) {
      throw UhfException('Failed to perform inventory: ${e.message}');
    }
  }

  // ============ Configuración de Potencia ============

  /// Establece la potencia de lectura y escritura
  /// [readPower] y [writePower] deben estar entre 5 y 33 dBm
  static Future<bool> setPower({
    required int readPower,
    required int writePower,
  }) async {
    if (readPower < 5 || readPower > 33 || writePower < 5 || writePower > 33) {
      throw UhfException('Power must be between 5 and 33 dBm');
    }
    try {
      final result = await _methodChannel.invokeMethod<Map>(
        'setPower',
        {'readPower': readPower, 'writePower': writePower},
      );
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to set power: ${e.message}');
    }
  }

  /// Obtiene la potencia actual de lectura y escritura
  static Future<Map<String, int>?> getPower() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('getPower');
      if (result == null) return null;
      return {
        'readPower': result['readPower'] as int,
        'writePower': result['writePower'] as int,
      };
    } on PlatformException catch (e) {
      throw UhfException('Failed to get power: ${e.message}');
    }
  }

  // ============ Configuración de Región ============

  /// Establece la región de frecuencia
  static Future<bool> setRegion(FrequencyRegion region) async {
    try {
      final result = await _methodChannel.invokeMethod<Map>(
        'setRegion',
        {'region': region.value},
      );
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to set region: ${e.message}');
    }
  }

  /// Obtiene la región de frecuencia actual
  static Future<String?> getRegion() async {
    try {
      return await _methodChannel.invokeMethod<String>('getRegion');
    } on PlatformException catch (e) {
      throw UhfException('Failed to get region: ${e.message}');
    }
  }

  // ============ Lectura/Escritura de Tags ============

  /// Lee datos de un tag
  /// [bank] banco de memoria (EPC, TID, USER, RESERVED)
  /// [startAddr] dirección inicial en words
  /// [length] longitud en words
  /// [password] contraseña de acceso (8 caracteres hex, default: 00000000)
  /// [timeout] tiempo de espera en ms
  static Future<String?> readTagData({
    required MemoryBank bank,
    int startAddr = 0,
    int length = 6,
    String password = '00000000',
    int timeout = 1000,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('readTagData', {
        'bank': bank.value,
        'startAddr': startAddr,
        'length': length,
        'password': password,
        'timeout': timeout,
      });
      if (result?['success'] == true) {
        return result?['data'] as String?;
      }
      return null;
    } on PlatformException catch (e) {
      throw UhfException('Failed to read tag data: ${e.message}');
    }
  }

  /// Escribe datos en un tag
  /// [bank] banco de memoria
  /// [startAddr] dirección inicial en words
  /// [data] datos en formato hexadecimal
  /// [password] contraseña de acceso
  /// [timeout] tiempo de espera en ms
  static Future<bool> writeTagData({
    required MemoryBank bank,
    required String data,
    int startAddr = 0,
    String password = '00000000',
    int timeout = 1000,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('writeTagData', {
        'bank': bank.value,
        'startAddr': startAddr,
        'data': data,
        'password': password,
        'timeout': timeout,
      });
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to write tag data: ${e.message}');
    }
  }

  /// Escribe un nuevo EPC en el tag
  /// [epc] nuevo EPC en formato hexadecimal
  /// [password] contraseña de acceso
  /// [timeout] tiempo de espera en ms
  static Future<bool> writeTagEpc({
    required String epc,
    String password = '00000000',
    int timeout = 1000,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('writeTagEpc', {
        'epc': epc,
        'password': password,
        'timeout': timeout,
      });
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to write tag EPC: ${e.message}');
    }
  }

  // ============ Lock/Kill Tags ============

  /// Bloquea un banco de memoria del tag
  static Future<bool> lockTag({
    required LockObject lockObject,
    required LockType lockType,
    required String password,
    int timeout = 1000,
  }) async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('lockTag', {
        'lockObject': lockObject.value,
        'lockType': lockType.value,
        'password': password,
        'timeout': timeout,
      });
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to lock tag: ${e.message}');
    }
  }

  /// Destruye permanentemente un tag (IRREVERSIBLE)
  /// La contraseña de kill NO puede ser 00000000
  static Future<bool> killTag({
    required String killPassword,
    int timeout = 1000,
  }) async {
    if (killPassword == '00000000' || killPassword.isEmpty) {
      throw UhfException('Kill password cannot be zero or empty');
    }
    try {
      final result = await _methodChannel.invokeMethod<Map>('killTag', {
        'killPassword': killPassword,
        'timeout': timeout,
      });
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to kill tag: ${e.message}');
    }
  }

  // ============ Filtros de Inventario ============

  /// Establece un filtro para el inventario
  /// [filterData] datos del filtro en hexadecimal
  /// [bank] banco a filtrar (EPC, TID, USER)
  /// [startAddr] dirección inicial en words
  /// [matching] true para incluir coincidencias, false para excluirlas
  static Future<bool> setInventoryFilter({
    required String filterData,
    required MemoryBank bank,
    int startAddr = 0,
    bool matching = true,
  }) async {
    try {
      final result =
          await _methodChannel.invokeMethod<Map>('setInventoryFilter', {
        'filterData': filterData,
        'bank': bank.value,
        'startAddr': startAddr,
        'matching': matching,
      });
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to set inventory filter: ${e.message}');
    }
  }

  /// Cancela el filtro de inventario activo
  static Future<bool> cancelInventoryFilter() async {
    try {
      final result =
          await _methodChannel.invokeMethod<Map>('cancelInventoryFilter');
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to cancel inventory filter: ${e.message}');
    }
  }

  // ============ Frecuencias ============

  /// Obtiene los puntos de frecuencia actuales en kHz
  static Future<List<int>?> getFrequencyPoints() async {
    try {
      final result =
          await _methodChannel.invokeMethod<List>('getFrequencyPoints');
      return result?.cast<int>();
    } on PlatformException catch (e) {
      throw UhfException('Failed to get frequency points: ${e.message}');
    }
  }

  /// Establece los puntos de frecuencia en kHz
  static Future<bool> setFrequencyPoints(List<int> points) async {
    try {
      final result = await _methodChannel.invokeMethod<Map>(
        'setFrequencyPoints',
        {'points': points},
      );
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to set frequency points: ${e.message}');
    }
  }

  // ============ Utilidades ============

  /// Obtiene la temperatura del módulo
  static Future<int?> getTemperature() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('getTemperature');
      return result?['temperature'] as int?;
    } on PlatformException catch (e) {
      throw UhfException('Failed to get temperature: ${e.message}');
    }
  }
}

/// Excepción personalizada para errores del UHF
class UhfException implements Exception {
  final String message;
  UhfException(this.message);

  @override
  String toString() => 'UhfException: $message';
}
```

---

## Paso 5: Ejemplo de Uso

### 5.1 Aplicación de Ejemplo

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uhf_rfid_plugin/uhf_rfid_plugin.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UHF RFID Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const RfidScannerPage(),
    );
  }
}

class RfidScannerPage extends StatefulWidget {
  const RfidScannerPage({super.key});

  @override
  State<RfidScannerPage> createState() => _RfidScannerPageState();
}

class _RfidScannerPageState extends State<RfidScannerPage> {
  bool _isInitialized = false;
  bool _isScanning = false;
  String? _hardwareVersion;
  int? _temperature;
  Map<String, int>? _power;

  final Map<String, RfidTag> _tags = {};
  StreamSubscription<RfidTag>? _tagSubscription;

  @override
  void initState() {
    super.initState();
    _initReader();
  }

  @override
  void dispose() {
    _tagSubscription?.cancel();
    if (_isInitialized) {
      UhfRfidPlugin.close();
    }
    super.dispose();
  }

  Future<void> _initReader() async {
    try {
      final success = await UhfRfidPlugin.init();
      if (success) {
        final version = await UhfRfidPlugin.getHardwareVersion();
        final power = await UhfRfidPlugin.getPower();
        final temp = await UhfRfidPlugin.getTemperature();

        // Configurar potencia por defecto
        await UhfRfidPlugin.setPower(readPower: 26, writePower: 26);

        // Suscribirse al stream de tags
        _tagSubscription = UhfRfidPlugin.tagStream.listen(_onTagRead);

        setState(() {
          _isInitialized = true;
          _hardwareVersion = version;
          _power = power;
          _temperature = temp;
        });
      }
    } on UhfException catch (e) {
      _showError(e.message);
    }
  }

  void _onTagRead(RfidTag tag) {
    setState(() {
      // Actualizar conteo si ya existe
      if (_tags.containsKey(tag.epc)) {
        final existing = _tags[tag.epc]!;
        _tags[tag.epc] = RfidTag(
          epc: tag.epc,
          rssi: tag.rssi,
          count: existing.count + 1,
          antenna: tag.antenna,
        );
      } else {
        _tags[tag.epc] = tag;
      }
    });
  }

  Future<void> _toggleScanning() async {
    try {
      if (_isScanning) {
        await UhfRfidPlugin.stopInventory();
      } else {
        await UhfRfidPlugin.startInventory();
      }
      setState(() => _isScanning = !_isScanning);
    } on UhfException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _singleScan() async {
    try {
      final tags = await UhfRfidPlugin.inventoryOnce(timeout: 500);
      for (final tag in tags) {
        _onTagRead(tag);
      }
    } on UhfException catch (e) {
      _showError(e.message);
    }
  }

  void _clearTags() {
    setState(() => _tags.clear());
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UHF RFID Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _clearTags,
          ),
        ],
      ),
      body: Column(
        children: [
          // Info del dispositivo
          Card(
            margin: const EdgeInsets.all(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _isInitialized ? Icons.check_circle : Icons.error,
                        color: _isInitialized ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isInitialized ? 'Conectado' : 'Desconectado',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  if (_hardwareVersion != null) ...[
                    const SizedBox(height: 4),
                    Text('Hardware: $_hardwareVersion'),
                  ],
                  if (_temperature != null) ...[
                    Text('Temperatura: $_temperature°C'),
                  ],
                  if (_power != null) ...[
                    Text('Potencia R/W: ${_power!['readPower']}/${_power!['writePower']} dBm'),
                  ],
                ],
              ),
            ),
          ),

          // Botones de control
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isInitialized ? _toggleScanning : null,
                    icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
                    label: Text(_isScanning ? 'Detener' : 'Escanear'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isScanning ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isInitialized && !_isScanning ? _singleScan : null,
                    icon: const Icon(Icons.touch_app),
                    label: const Text('Una vez'),
                  ),
                ),
              ],
            ),
          ),

          // Contador de tags
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              'Tags encontrados: ${_tags.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),

          // Lista de tags
          Expanded(
            child: ListView.builder(
              itemCount: _tags.length,
              itemBuilder: (context, index) {
                final tag = _tags.values.elementAt(index);
                return ListTile(
                  leading: CircleAvatar(
                    child: Text('${tag.count}'),
                  ),
                  title: Text(
                    tag.epc,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  subtitle: Text('RSSI: ${tag.rssi} dBm'),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showTagDetails(tag),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showTagDetails(RfidTag tag) {
    showModalBottomSheet(
      context: context,
      builder: (context) => TagDetailsSheet(tag: tag),
    );
  }
}

class TagDetailsSheet extends StatefulWidget {
  final RfidTag tag;

  const TagDetailsSheet({super.key, required this.tag});

  @override
  State<TagDetailsSheet> createState() => _TagDetailsSheetState();
}

class _TagDetailsSheetState extends State<TagDetailsSheet> {
  String? _tidData;
  String? _userData;
  bool _isLoading = false;

  Future<void> _readTid() async {
    setState(() => _isLoading = true);
    try {
      // Filtrar por EPC para leer solo este tag
      await UhfRfidPlugin.setInventoryFilter(
        filterData: widget.tag.epc,
        bank: MemoryBank.epc,
        startAddr: 2,
      );

      final tid = await UhfRfidPlugin.readTagData(
        bank: MemoryBank.tid,
        startAddr: 0,
        length: 6,
      );

      await UhfRfidPlugin.cancelInventoryFilter();

      setState(() => _tidData = tid);
    } on UhfException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _readUserData() async {
    setState(() => _isLoading = true);
    try {
      await UhfRfidPlugin.setInventoryFilter(
        filterData: widget.tag.epc,
        bank: MemoryBank.epc,
        startAddr: 2,
      );

      final userData = await UhfRfidPlugin.readTagData(
        bank: MemoryBank.user,
        startAddr: 0,
        length: 16,
      );

      await UhfRfidPlugin.cancelInventoryFilter();

      setState(() => _userData = userData);
    } on UhfException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('EPC:', style: Theme.of(context).textTheme.labelSmall),
          SelectableText(
            widget.tag.epc,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          ),
          const SizedBox(height: 16),

          Row(
            children: [
              ElevatedButton(
                onPressed: _isLoading ? null : _readTid,
                child: const Text('Leer TID'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isLoading ? null : _readUserData,
                child: const Text('Leer USER'),
              ),
            ],
          ),

          if (_isLoading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],

          if (_tidData != null) ...[
            const SizedBox(height: 16),
            Text('TID:', style: Theme.of(context).textTheme.labelSmall),
            SelectableText(
              _tidData!,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],

          if (_userData != null) ...[
            const SizedBox(height: 16),
            Text('USER Data:', style: Theme.of(context).textTheme.labelSmall),
            SelectableText(
              _userData!,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
```

---

## Paso 6: Configuración del Proyecto Flutter Principal

### 6.1 Agregar el Plugin como Dependencia

En el `pubspec.yaml` de tu aplicación:

```yaml
dependencies:
  flutter:
    sdk: flutter
  uhf_rfid_plugin:
    path: ../uhf_rfid_plugin  # Ruta al plugin local
```

O si publicas el plugin:

```yaml
dependencies:
  uhf_rfid_plugin: ^1.0.0
```

### 6.2 android/app/build.gradle

```groovy
android {
    defaultConfig {
        minSdkVersion 21

        ndk {
            abiFilters 'armeabi-v7a', 'arm64-v8a'
        }
    }
}
```

---

## Referencia Rápida de la API

### Métodos Disponibles

| Método | Descripción |
|--------|-------------|
| `init()` | Inicializa el lector |
| `close()` | Cierra la conexión |
| `getHardwareVersion()` | Obtiene versión del hardware |
| `startInventory()` | Inicia escaneo continuo |
| `stopInventory()` | Detiene escaneo |
| `inventoryOnce(timeout)` | Escaneo único por tiempo |
| `setPower(read, write)` | Configura potencia (5-33 dBm) |
| `getPower()` | Obtiene potencia actual |
| `setRegion(region)` | Configura región de frecuencia |
| `getRegion()` | Obtiene región actual |
| `readTagData(...)` | Lee datos de un tag |
| `writeTagData(...)` | Escribe datos en un tag |
| `writeTagEpc(...)` | Escribe nuevo EPC |
| `lockTag(...)` | Bloquea banco de memoria |
| `killTag(...)` | Destruye un tag (IRREVERSIBLE) |
| `setInventoryFilter(...)` | Aplica filtro de inventario |
| `cancelInventoryFilter()` | Cancela filtro |
| `getFrequencyPoints()` | Obtiene frecuencias en kHz |
| `setFrequencyPoints(...)` | Configura frecuencias |
| `getTemperature()` | Temperatura del módulo |

### Bancos de Memoria

| Banco | Valor | Descripción |
|-------|-------|-------------|
| RESERVED | 0 | Passwords (acceso/kill) |
| EPC | 1 | Electronic Product Code |
| TID | 2 | Tag Identifier (solo lectura) |
| USER | 3 | Memoria de usuario |

### Regiones de Frecuencia

| Región | Frecuencias |
|--------|-------------|
| CHN | 920.625 - 924.375 MHz |
| USA | 902.75 - 927.25 MHz |
| EU | 865.7 - 867.5 MHz |
| KOREA | 917.1 - 923.3 MHz |

---

## Solución de Problemas

### Error: "Reader not initialized"
- Verificar que el dispositivo tenga el módulo UHF hardware
- Asegurar que se llamó a `init()` antes de cualquier operación

### Error: "Failed to load native library"
- Verificar que las librerías .so estén en las carpetas correctas
- Confirmar que el ABI del dispositivo es compatible (arm64-v8a o armeabi-v7a)

### Tags no detectados
- Aumentar la potencia con `setPower()`
- Verificar la región de frecuencia
- Acercar los tags al lector
- Verificar que no haya filtros activos

### Escritura fallida
- Verificar que el tag no esté bloqueado
- Usar la contraseña correcta
- El tag debe estar dentro del rango durante toda la operación

---

## Notas Importantes

1. **Solo Android**: Este SDK es exclusivo para Android debido a las dependencias de hardware específicas.

2. **Dispositivo Específico**: Diseñado para dispositivos PDA con módulo UHF R2000 integrado.

3. **Permisos**: No requiere permisos especiales ya que la comunicación es por puerto serial interno.

4. **Ciclo de Vida**: Siempre llamar `close()` al salir de la aplicación para liberar recursos.

5. **Thread Safety**: Las operaciones del SDK se ejecutan en un thread separado para no bloquear la UI.
