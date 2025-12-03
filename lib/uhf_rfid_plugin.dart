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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RfidTag &&
          runtimeType == other.runtimeType &&
          epc == other.epc;

  @override
  int get hashCode => epc.hashCode;
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

/// Evento del botón físico del PDA
class TriggerButtonEvent {
  final int keyCode;
  final String action; // "down" or "up"
  final bool isReading;

  TriggerButtonEvent({
    required this.keyCode,
    required this.action,
    required this.isReading,
  });

  factory TriggerButtonEvent.fromMap(Map<dynamic, dynamic> map) {
    return TriggerButtonEvent(
      keyCode: map['keyCode'] as int? ?? 0,
      action: map['action'] as String? ?? '',
      isReading: map['isReading'] as bool? ?? false,
    );
  }

  /// Indica si el botón fue presionado
  bool get isPressed => action == 'down';

  /// Indica si el botón fue soltado
  bool get isReleased => action == 'up';

  @override
  String toString() =>
      'TriggerButtonEvent(keyCode: $keyCode, action: $action, isReading: $isReading)';
}

/// Resultado del escaneo de código de barras/QR
class BarcodeResult {
  final String barcode;
  final String rawData;
  final int length;
  final int timestamp;

  BarcodeResult({
    required this.barcode,
    required this.rawData,
    required this.length,
    required this.timestamp,
  });

  factory BarcodeResult.fromMap(Map<dynamic, dynamic> map) {
    return BarcodeResult(
      barcode: map['barcode'] as String? ?? '',
      rawData: map['rawData'] as String? ?? '',
      length: map['length'] as int? ?? 0,
      timestamp: map['timestamp'] as int? ?? 0,
    );
  }

  /// Fecha y hora del escaneo
  DateTime get dateTime => DateTime.fromMillisecondsSinceEpoch(timestamp);

  @override
  String toString() =>
      'BarcodeResult(barcode: $barcode, length: $length, timestamp: $timestamp)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BarcodeResult &&
          runtimeType == other.runtimeType &&
          barcode == other.barcode &&
          timestamp == other.timestamp;

  @override
  int get hashCode => barcode.hashCode ^ timestamp.hashCode;
}

/// Enumeración de modos de escaneo de barras
enum BarcodeScanMode {
  /// Modo BroadcastReceiver - los datos se envían via stream
  broadcast(0),
  /// Modo Focus Input - los datos se insertan en el campo de texto con foco
  focusInput(1);

  final int value;
  const BarcodeScanMode(this.value);
}

/// Plugin principal para UHF RFID y Barcode Scanner
class UhfRfidPlugin {
  static const MethodChannel _methodChannel =
      MethodChannel('com.example.uhf_rfid_plugin/methods');

  static const EventChannel _eventChannel =
      EventChannel('com.example.uhf_rfid_plugin/tags');

  static const EventChannel _buttonEventChannel =
      EventChannel('com.example.uhf_rfid_plugin/button');

  static const EventChannel _barcodeEventChannel =
      EventChannel('com.example.uhf_rfid_plugin/barcode');

  static Stream<RfidTag>? _tagStream;
  static Stream<TriggerButtonEvent>? _buttonStream;
  static Stream<BarcodeResult>? _barcodeStream;

  /// Stream de tags leídos en tiempo real
  static Stream<RfidTag> get tagStream {
    _tagStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((event) => RfidTag.fromMap(event as Map<dynamic, dynamic>));
    return _tagStream!;
  }

  /// Stream de eventos del botón físico (trigger)
  /// Escucha este stream para recibir eventos cuando el usuario
  /// presiona/suelta el botón físico del PDA
  static Stream<TriggerButtonEvent> get buttonStream {
    _buttonStream ??= _buttonEventChannel
        .receiveBroadcastStream()
        .map((event) =>
            TriggerButtonEvent.fromMap(event as Map<dynamic, dynamic>));
    return _buttonStream!;
  }

  /// Stream de códigos de barras/QR escaneados
  /// Escucha este stream para recibir los resultados del escaneo
  static Stream<BarcodeResult> get barcodeStream {
    _barcodeStream ??= _barcodeEventChannel
        .receiveBroadcastStream()
        .map((event) =>
            BarcodeResult.fromMap(event as Map<dynamic, dynamic>));
    return _barcodeStream!;
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

  // ============ Botón Físico (Trigger) ============

  /// Habilita o deshabilita el botón físico del PDA
  /// Cuando está habilitado, el botón toggle el inventario automáticamente
  static Future<bool> setTriggerButtonEnabled(bool enabled) async {
    try {
      final result = await _methodChannel.invokeMethod<Map>(
        'setTriggerButtonEnabled',
        {'enabled': enabled},
      );
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to set trigger button enabled: ${e.message}');
    }
  }

  /// Verifica si el botón físico está habilitado
  static Future<bool> isTriggerButtonEnabled() async {
    try {
      final result =
          await _methodChannel.invokeMethod<Map>('isTriggerButtonEnabled');
      return result?['enabled'] as bool? ?? true;
    } on PlatformException catch (e) {
      throw UhfException('Failed to get trigger button state: ${e.message}');
    }
  }

  /// Verifica si el lector está actualmente escaneando
  static Future<bool> isReading() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('isReading');
      return result?['isReading'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to get reading status: ${e.message}');
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

  // ============ Barcode/QR Scanner ============

  /// Inicializa el escáner de códigos de barras/QR
  /// Debe llamarse antes de usar cualquier función del escáner
  /// Automáticamente configura el modo BroadcastReceiver para recibir datos via stream
  static Future<bool> initBarcode() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('initBarcode');
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to initialize barcode scanner: ${e.message}');
    }
  }

  /// Inicia un escaneo de código de barras/QR
  /// Los resultados se reciben a través de [barcodeStream]
  static Future<bool> startBarcodeScan() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('startBarcodeScan');
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to start barcode scan: ${e.message}');
    }
  }

  /// Detiene el escaneo de código de barras/QR en curso
  static Future<bool> stopBarcodeScan() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('stopBarcodeScan');
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to stop barcode scan: ${e.message}');
    }
  }

  /// Cierra el escáner de códigos de barras
  /// Libera los recursos del escáner
  static Future<bool> closeBarcode() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('closeBarcode');
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to close barcode scanner: ${e.message}');
    }
  }

  /// Establece el modo de escaneo
  /// [mode] puede ser:
  /// - [BarcodeScanMode.broadcast]: Los datos se envían via stream (recomendado)
  /// - [BarcodeScanMode.focusInput]: Los datos se insertan en el campo de texto con foco
  static Future<bool> setBarcodeScanMode(BarcodeScanMode mode) async {
    try {
      final result = await _methodChannel.invokeMethod<Map>(
        'setBarcodeScanMode',
        {'mode': mode.value},
      );
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to set barcode scan mode: ${e.message}');
    }
  }

  /// Establece el timeout del escaneo en milisegundos
  /// [timeout] debe ser uno de: 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000
  /// El valor por defecto es 5000ms
  static Future<bool> setBarcodeTimeout(int timeout) async {
    final validTimeouts = [1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000];
    if (!validTimeouts.contains(timeout)) {
      throw UhfException('Invalid timeout. Must be one of: $validTimeouts');
    }
    try {
      final result = await _methodChannel.invokeMethod<Map>(
        'setBarcodeTimeout',
        {'timeout': timeout},
      );
      return result?['success'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to set barcode timeout: ${e.message}');
    }
  }

  /// Verifica si el escáner de barras está inicializado
  static Future<bool> isBarcodeInitialized() async {
    try {
      final result = await _methodChannel.invokeMethod<Map>('isBarcodeInitialized');
      return result?['initialized'] as bool? ?? false;
    } on PlatformException catch (e) {
      throw UhfException('Failed to check barcode initialization: ${e.message}');
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
