# UHF RFID Plugin para Flutter

Plugin Flutter para integración con lectores UHF RFID R2000 (SDK v2.5) y escáner de códigos de barras/QR en dispositivos PDA7100 y similares.

## Características

### UHF RFID
- Inicializar/cerrar lector UHF
- Inventario continuo y único de tags EPC Gen2
- Lectura/escritura de datos en bancos EPC, TID, USER y RESERVED
- Configuración de potencia (5-33 dBm)
- Configuración de región de frecuencia (USA, EU, China, Korea)
- Filtros de inventario
- Soporte para botón físico (trigger)
- Operaciones de Lock/Kill de tags
- Lectura de temperatura del módulo

### Escáner de Barcode/QR
- Inicializar/cerrar escáner
- Escaneo de códigos de barras y QR
- Timeout configurable (1-10 segundos)
- Selección de modo (Broadcast o Focus Input)
- Resultados en tiempo real via stream

## Requisitos

- Flutter >= 3.3.0
- Android SDK >= 21 (Android 5.0+)
- Dispositivo PDA con módulo UHF R2000 integrado

## Instalación

### Dependencia Local

```yaml
dependencies:
  uhf_rfid_plugin:
    path: ../uhf_rfid_plugin
```

### Desde Git

```yaml
dependencies:
  uhf_rfid_plugin:
    git:
      url: https://github.com/tu-usuario/uhf_rfid_plugin.git
```

### Configuración Android

En `android/app/build.gradle`:

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

## Uso Básico

### Importar el Plugin

```dart
import 'package:uhf_rfid_plugin/uhf_rfid_plugin.dart';
```

---

## UHF RFID

### Inicialización

```dart
// Inicializar el lector
final success = await UhfRfidPlugin.init();
if (success) {
  print('Lector UHF inicializado correctamente');

  // Obtener información del hardware
  final version = await UhfRfidPlugin.getHardwareVersion();
  final temp = await UhfRfidPlugin.getTemperature();
  print('Hardware: $version, Temperatura: $temp°C');
}

// Al terminar, cerrar el lector
await UhfRfidPlugin.close();
```

### Inventario Continuo

```dart
// Suscribirse al stream de tags
final subscription = UhfRfidPlugin.tagStream.listen((RfidTag tag) {
  print('Tag detectado: ${tag.epc}');
  print('RSSI: ${tag.rssi} dBm');
  print('Lecturas: ${tag.count}');
});

// Iniciar inventario continuo
await UhfRfidPlugin.startInventory();

// ... escanear tags ...

// Detener inventario
await UhfRfidPlugin.stopInventory();

// Cancelar suscripción al salir
subscription.cancel();
```

### Inventario Único

```dart
// Realizar una lectura única (500ms de timeout)
final List<RfidTag> tags = await UhfRfidPlugin.inventoryOnce(timeout: 500);

print('Tags encontrados: ${tags.length}');
for (final tag in tags) {
  print('EPC: ${tag.epc}, RSSI: ${tag.rssi}');
}
```

### Configurar Potencia

```dart
// Establecer potencia de lectura y escritura (5-33 dBm)
await UhfRfidPlugin.setPower(readPower: 26, writePower: 26);

// Obtener potencia actual
final power = await UhfRfidPlugin.getPower();
if (power != null) {
  print('Potencia lectura: ${power['readPower']} dBm');
  print('Potencia escritura: ${power['writePower']} dBm');
}
```

### Configurar Región de Frecuencia

```dart
// Establecer región
await UhfRfidPlugin.setRegion(FrequencyRegion.usa);

// Opciones disponibles:
// - FrequencyRegion.usa     (902.75 - 927.25 MHz)
// - FrequencyRegion.europe  (865.7 - 867.5 MHz)
// - FrequencyRegion.china   (920.625 - 924.375 MHz)
// - FrequencyRegion.korea   (917.1 - 923.3 MHz)

// Obtener región actual
final region = await UhfRfidPlugin.getRegion();
print('Región actual: $region');
```

### Leer Datos de un Tag

```dart
// Leer banco TID (identificador único del tag - solo lectura)
final tid = await UhfRfidPlugin.readTagData(
  bank: MemoryBank.tid,
  startAddr: 0,
  length: 6,  // palabras de 16 bits
);
print('TID: $tid');

// Leer banco USER (memoria de usuario)
final userData = await UhfRfidPlugin.readTagData(
  bank: MemoryBank.user,
  startAddr: 0,
  length: 16,
  password: '00000000',  // Contraseña de acceso (8 hex chars)
  timeout: 1000,         // Timeout en ms
);
print('User Data: $userData');

// Leer banco EPC
final epc = await UhfRfidPlugin.readTagData(
  bank: MemoryBank.epc,
  startAddr: 2,  // El EPC comienza en la palabra 2
  length: 6,
);
```

### Escribir Datos en un Tag

```dart
// Escribir en banco USER
final success = await UhfRfidPlugin.writeTagData(
  bank: MemoryBank.user,
  startAddr: 0,
  data: 'AABBCCDD11223344',  // Datos en hexadecimal
  password: '00000000',
  timeout: 1000,
);

if (success) {
  print('Datos escritos correctamente');
}

// Escribir nuevo EPC
await UhfRfidPlugin.writeTagEpc(
  epc: 'E20000000000000000001234',
  password: '00000000',
  timeout: 1000,
);
```

### Filtros de Inventario

```dart
// Aplicar filtro para leer solo tags con EPC que comience con "E200"
await UhfRfidPlugin.setInventoryFilter(
  filterData: 'E200',
  bank: MemoryBank.epc,
  startAddr: 2,       // EPC comienza en palabra 2
  matching: true,     // true = incluir coincidencias, false = excluir
);

// Realizar inventario (solo tags que coincidan)
await UhfRfidPlugin.startInventory();

// ... escanear ...

// Cancelar filtro
await UhfRfidPlugin.cancelInventoryFilter();
```

### Bloquear un Tag

```dart
// Bloquear banco USER
await UhfRfidPlugin.lockTag(
  lockObject: LockObject.user,
  lockType: LockType.lock,
  password: 'AABBCCDD',  // Contraseña de acceso
  timeout: 1000,
);

// Opciones de LockObject:
// - accessPassword: Contraseña de acceso
// - killPassword:   Contraseña de kill
// - epc:            Banco EPC
// - tid:            Banco TID
// - user:           Banco USER

// Opciones de LockType:
// - unlock:      Desbloquear
// - lock:        Bloquear
// - permaLock:   Bloqueo permanente (irreversible)
// - permaUnlock: Desbloqueo permanente
```

### Destruir un Tag (Kill)

```dart
// ⚠️ ADVERTENCIA: Esta operación es IRREVERSIBLE
// El tag quedará permanentemente inutilizado

await UhfRfidPlugin.killTag(
  killPassword: 'AABBCCDD',  // NO puede ser 00000000
  timeout: 1000,
);
```

---

## Escáner de Códigos de Barras/QR

### Inicialización

```dart
// Inicializar el escáner
final success = await UhfRfidPlugin.initBarcode();
if (success) {
  print('Escáner de barcode inicializado');
}

// Al terminar, cerrar el escáner
await UhfRfidPlugin.closeBarcode();
```

### Escanear Códigos

```dart
// Suscribirse al stream de resultados
final subscription = UhfRfidPlugin.barcodeStream.listen((BarcodeResult result) {
  print('Código: ${result.barcode}');
  print('Longitud: ${result.length}');
  print('Hora: ${result.dateTime}');
});

// Iniciar escaneo (se detiene automáticamente al leer un código)
await UhfRfidPlugin.startBarcodeScan();

// O detener manualmente
await UhfRfidPlugin.stopBarcodeScan();

// Cancelar suscripción al salir
subscription.cancel();
```

### Configurar Timeout

```dart
// Establecer tiempo máximo de escaneo
// Valores permitidos: 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000 ms
await UhfRfidPlugin.setBarcodeTimeout(5000);  // 5 segundos
```

### Configurar Modo de Escaneo

```dart
// Modo Broadcast (recomendado) - resultados via stream
await UhfRfidPlugin.setBarcodeScanMode(BarcodeScanMode.broadcast);

// Modo Focus Input - inserta texto en el campo con foco
await UhfRfidPlugin.setBarcodeScanMode(BarcodeScanMode.focusInput);
```

---

## Botón Físico (Trigger)

El plugin soporta el botón físico de los dispositivos PDA:

```dart
// Escuchar eventos del botón físico
UhfRfidPlugin.buttonStream.listen((TriggerButtonEvent event) {
  if (event.isPressed) {
    print('Botón presionado');
  } else if (event.isReleased) {
    print('Botón soltado');
    print('¿Estaba leyendo?: ${event.isReading}');
  }
});

// Habilitar/deshabilitar el botón
await UhfRfidPlugin.setTriggerButtonEnabled(true);

// Verificar estado
final enabled = await UhfRfidPlugin.isTriggerButtonEnabled();

// Verificar si está escaneando actualmente
final reading = await UhfRfidPlugin.isReading();
```

---

## Referencia de API

### Métodos UHF RFID

| Método | Descripción |
|--------|-------------|
| `init()` | Inicializa el lector UHF |
| `close()` | Cierra la conexión con el lector |
| `getHardwareVersion()` | Obtiene la versión del hardware |
| `startInventory()` | Inicia inventario continuo |
| `stopInventory()` | Detiene inventario continuo |
| `inventoryOnce({timeout})` | Realiza inventario único |
| `setPower({readPower, writePower})` | Configura potencia (5-33 dBm) |
| `getPower()` | Obtiene potencia actual |
| `setRegion(region)` | Configura región de frecuencia |
| `getRegion()` | Obtiene región actual |
| `readTagData({...})` | Lee datos de un tag |
| `writeTagData({...})` | Escribe datos en un tag |
| `writeTagEpc({...})` | Escribe nuevo EPC |
| `lockTag({...})` | Bloquea banco de memoria |
| `killTag({...})` | Destruye tag (IRREVERSIBLE) |
| `setInventoryFilter({...})` | Aplica filtro |
| `cancelInventoryFilter()` | Cancela filtro |
| `getFrequencyPoints()` | Obtiene frecuencias en kHz |
| `setFrequencyPoints(points)` | Configura frecuencias |
| `getTemperature()` | Obtiene temperatura del módulo |
| `setTriggerButtonEnabled(enabled)` | Habilita/deshabilita botón físico |
| `isTriggerButtonEnabled()` | Verifica si el botón está habilitado |
| `isReading()` | Verifica si está escaneando |

### Métodos Barcode/QR

| Método | Descripción |
|--------|-------------|
| `initBarcode()` | Inicializa el escáner |
| `closeBarcode()` | Cierra el escáner |
| `startBarcodeScan()` | Inicia escaneo |
| `stopBarcodeScan()` | Detiene escaneo |
| `setBarcodeScanMode(mode)` | Configura modo de escaneo |
| `setBarcodeTimeout(timeout)` | Configura timeout (1000-10000ms) |
| `isBarcodeInitialized()` | Verifica si está inicializado |

### Streams

| Stream | Tipo | Descripción |
|--------|------|-------------|
| `tagStream` | `Stream<RfidTag>` | Tags RFID detectados |
| `buttonStream` | `Stream<TriggerButtonEvent>` | Eventos del botón físico |
| `barcodeStream` | `Stream<BarcodeResult>` | Códigos de barras escaneados |

---

## Modelos de Datos

### RfidTag

```dart
class RfidTag {
  final String epc;    // Código EPC en hexadecimal
  final int rssi;      // Intensidad de señal en dBm
  final int count;     // Número de lecturas
  final int? antenna;  // Antena que detectó el tag
}
```

### BarcodeResult

```dart
class BarcodeResult {
  final String barcode;   // Código escaneado
  final String rawData;   // Datos sin procesar
  final int length;       // Longitud del código
  final int timestamp;    // Timestamp en milisegundos

  DateTime get dateTime;  // Fecha y hora del escaneo
}
```

### TriggerButtonEvent

```dart
class TriggerButtonEvent {
  final int keyCode;    // Código de la tecla
  final String action;  // "down" o "up"
  final bool isReading; // Estado del lector

  bool get isPressed;   // ¿Botón presionado?
  bool get isReleased;  // ¿Botón soltado?
}
```

---

## Enumeraciones

### MemoryBank

```dart
enum MemoryBank {
  reserved(0), // Passwords (acceso/kill)
  epc(1),      // Electronic Product Code
  tid(2),      // Tag Identifier (solo lectura)
  user(3);     // Memoria de usuario
}
```

### FrequencyRegion

```dart
enum FrequencyRegion {
  china('CHN'),    // 920.625 - 924.375 MHz
  usa('USA'),      // 902.75 - 927.25 MHz
  europe('EU'),    // 865.7 - 867.5 MHz
  korea('KOREA');  // 917.1 - 923.3 MHz
}
```

### LockObject

```dart
enum LockObject {
  accessPassword, // Contraseña de acceso
  killPassword,   // Contraseña de kill
  epc,            // Banco EPC
  tid,            // Banco TID
  user;           // Banco USER
}
```

### LockType

```dart
enum LockType {
  unlock,      // Desbloquear
  lock,        // Bloquear
  permaLock,   // Bloqueo permanente
  permaUnlock; // Desbloqueo permanente
}
```

### BarcodeScanMode

```dart
enum BarcodeScanMode {
  broadcast,   // Resultados via barcodeStream
  focusInput;  // Resultados al campo de texto con foco
}
```

---

## Manejo de Errores

Todos los métodos pueden lanzar `UhfException`:

```dart
try {
  await UhfRfidPlugin.startInventory();
} on UhfException catch (e) {
  print('Error: ${e.message}');
}
```

---

## Ejemplo Completo

Ver el directorio [example/](example/) para una aplicación de demostración completa que incluye:

- Escaneo RFID con visualización en tiempo real
- Vista de detalles de tag (TID, USER data)
- Configuración de potencia y región
- Escaneo de códigos de barras/QR con historial
- Timeout configurable
- Soporte para botón físico

---

## Solución de Problemas

### Error: "Reader not initialized"
- Verificar que el dispositivo tenga el módulo UHF hardware
- Asegurar que se llamó a `init()` antes de cualquier operación

### Error: "Failed to load native library"
- Verificar que las librerías .so estén en las carpetas correctas
- Confirmar que el ABI del dispositivo es compatible (arm64-v8a o armeabi-v7a)

### Tags no detectados
- Aumentar la potencia con `setPower()` (máximo 33 dBm)
- Verificar la región de frecuencia correcta para tu país
- Acercar los tags al lector
- Verificar que no haya filtros activos con `cancelInventoryFilter()`

### Escritura fallida
- Verificar que el tag no esté bloqueado
- Usar la contraseña correcta (por defecto: 00000000)
- El tag debe estar dentro del rango durante toda la operación
- Aumentar la potencia de escritura

### Escáner de barras no funciona
- Verificar que se llamó a `initBarcode()` primero
- Comprobar que el modo está configurado como `broadcast`
- Aumentar el timeout si los códigos no se detectan
- Verificar que el escáner no esté siendo usado por otra app

---

## Dispositivos Compatibles

- WYUAN PDA3109
- PDA7100
- Otros dispositivos con módulo UHF R2000 y decodificador de barcode

---

## Notas Importantes

1. **Solo Android**: Este SDK es exclusivo para Android debido a las dependencias de hardware específicas.

2. **Dispositivo Específico**: Diseñado para dispositivos PDA con módulo UHF R2000 integrado.

3. **Permisos**: No requiere permisos especiales ya que la comunicación es por puerto serial interno.

4. **Ciclo de Vida**: Siempre llamar `close()` y `closeBarcode()` al salir de la aplicación.

5. **Thread Safety**: Las operaciones se ejecutan en threads separados para no bloquear la UI.

6. **Kill Tag**: La operación `killTag()` es **IRREVERSIBLE** y destruye permanentemente el tag.

---

## Licencia

MIT License - Ver archivo LICENSE para más detalles.
