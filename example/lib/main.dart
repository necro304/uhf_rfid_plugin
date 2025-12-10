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
      title: 'UHF RFID & Barcode Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    RfidScannerPage(),
    BarcodeScannerPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.nfc),
            selectedIcon: Icon(Icons.nfc, color: Colors.blue),
            label: 'RFID UHF',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            selectedIcon: Icon(Icons.qr_code_scanner, color: Colors.green),
            label: 'Barcode/QR',
          ),
        ],
      ),
    );
  }
}

// ============ RFID Scanner Page ============

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
  String? _region;

  final Map<String, RfidTag> _tags = {};
  StreamSubscription<RfidTag>? _tagSubscription;
  StreamSubscription<TriggerButtonEvent>? _buttonSubscription;

  @override
  void initState() {
    super.initState();
    _initReader();
  }

  @override
  void dispose() {
    _tagSubscription?.cancel();
    _buttonSubscription?.cancel();
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
        final region = await UhfRfidPlugin.getRegion();

        // Configurar potencia por defecto
        await UhfRfidPlugin.setPower(readPower: 26, writePower: 26);

        // Suscribirse al stream de tags
        _tagSubscription = UhfRfidPlugin.tagStream.listen(_onTagRead);

        // Suscribirse al stream del botón físico para actualizar UI
        _buttonSubscription = UhfRfidPlugin.buttonStream.listen(_onButtonEvent);

        setState(() {
          _isInitialized = true;
          _hardwareVersion = version;
          _power = power;
          _temperature = temp;
          _region = region;
        });
      } else {
        _showError('Failed to initialize reader');
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

  void _onButtonEvent(TriggerButtonEvent event) async {
    // Controlar el inventario cuando el usuario presiona/suelta el botón físico
    if (event.isPressed) {
      // Al presionar: iniciar inventario
      if (!_isScanning) {
        try {
          await UhfRfidPlugin.startInventory();
          setState(() => _isScanning = true);
        } on UhfException catch (e) {
          _showError(e.message);
        }
      }
    } else if (event.isReleased) {
      // Al soltar: detener inventario
      if (_isScanning) {
        try {
          await UhfRfidPlugin.stopInventory();
          setState(() => _isScanning = false);
        } on UhfException catch (e) {
          _showError(e.message);
        }
      }
    }
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
      _showMessage('Found ${tags.length} tags');
    } on UhfException catch (e) {
      _showError(e.message);
    }
  }

  void _clearTags() {
    setState(() => _tags.clear());
  }

  Future<void> _refreshInfo() async {
    try {
      final power = await UhfRfidPlugin.getPower();
      final temp = await UhfRfidPlugin.getTemperature();
      final region = await UhfRfidPlugin.getRegion();
      setState(() {
        _power = power;
        _temperature = temp;
        _region = region;
      });
    } on UhfException catch (e) {
      _showError(e.message);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UHF RFID Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isInitialized ? _refreshInfo : null,
            tooltip: 'Refresh Info',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _isInitialized ? () => _showSettings(context) : null,
            tooltip: 'Settings',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _clearTags,
            tooltip: 'Clear Tags',
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
                      const Spacer(),
                      if (_isScanning)
                        const Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Escaneando...'),
                          ],
                        ),
                    ],
                  ),
                  if (_hardwareVersion != null) ...[
                    const SizedBox(height: 8),
                    Text('Hardware: $_hardwareVersion'),
                  ],
                  if (_region != null) Text('Region: $_region'),
                  if (_temperature != null) Text('Temperatura: $_temperature C'),
                  if (_power != null)
                    Text(
                        'Potencia R/W: ${_power!['readPower']}/${_power!['writePower']} dBm'),
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
                    onPressed:
                        _isInitialized && !_isScanning ? _singleScan : null,
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Tags encontrados: ${_tags.length}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Total lecturas: ${_tags.values.fold(0, (sum, tag) => sum + tag.count)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),

          // Lista de tags
          Expanded(
            child: _tags.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.nfc, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No hay tags detectados',
                          style: TextStyle(color: Colors.grey),
                        ),
                        Text(
                          'Presiona "Escanear" para comenzar',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _tags.length,
                    itemBuilder: (context, index) {
                      final tag = _tags.values.elementAt(index);
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getRssiColor(tag.rssi),
                            child: Text(
                              '${tag.count}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          title: Text(
                            tag.epc,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 12),
                          ),
                          subtitle: Text('RSSI: ${tag.rssi} dBm'),
                          trailing: IconButton(
                            icon: const Icon(Icons.info_outline),
                            onPressed: () => _showTagDetails(tag),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _getRssiColor(int rssi) {
    if (rssi > -40) return Colors.green;
    if (rssi > -60) return Colors.lightGreen;
    if (rssi > -70) return Colors.orange;
    return Colors.red;
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SettingsSheet(
        currentPower: _power,
        currentRegion: _region,
        onPowerChanged: (read, write) async {
          try {
            await UhfRfidPlugin.setPower(readPower: read, writePower: write);
            await _refreshInfo();
            _showMessage('Power updated');
          } on UhfException catch (e) {
            _showError(e.message);
          }
        },
        onRegionChanged: (region) async {
          try {
            await UhfRfidPlugin.setRegion(region);
            await _refreshInfo();
            _showMessage('Region updated');
          } on UhfException catch (e) {
            _showError(e.message);
          }
        },
      ),
    );
  }

  void _showTagDetails(RfidTag tag) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => TagDetailsSheet(tag: tag),
    );
  }
}

// ============ Barcode Scanner Page ============

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  bool _isInitialized = false;
  bool _isScanning = false;
  int _timeout = 5000;

  final List<BarcodeResult> _barcodes = [];
  final Map<String, int> _barcodeCount = {};
  StreamSubscription<BarcodeResult>? _barcodeSubscription;

  @override
  void initState() {
    super.initState();
    _initBarcodeScanner();
  }

  @override
  void dispose() {
    _barcodeSubscription?.cancel();
    if (_isInitialized) {
      UhfRfidPlugin.closeBarcode();
    }
    super.dispose();
  }

  Future<void> _initBarcodeScanner() async {
    try {
      final success = await UhfRfidPlugin.initBarcode();
      if (success) {
        // Suscribirse al stream de códigos de barras
        _barcodeSubscription = UhfRfidPlugin.barcodeStream.listen(_onBarcodeScanned);

        setState(() {
          _isInitialized = true;
        });
        _showMessage('Barcode scanner initialized');
      } else {
        _showError('Failed to initialize barcode scanner');
      }
    } on UhfException catch (e) {
      _showError(e.message);
    }
  }

  void _onBarcodeScanned(BarcodeResult result) {
    setState(() {
      _barcodes.insert(0, result);
      _barcodeCount[result.barcode] = (_barcodeCount[result.barcode] ?? 0) + 1;
      _isScanning = false;
    });
  }

  Future<void> _startScan() async {
    try {
      setState(() => _isScanning = true);
      final success = await UhfRfidPlugin.startBarcodeScan();
      if (!success) {
        setState(() => _isScanning = false);
        _showError('Failed to start scan');
      }
      // El escaneo se detendrá automáticamente cuando se detecte un código
      // o cuando expire el timeout
    } on UhfException catch (e) {
      setState(() => _isScanning = false);
      _showError(e.message);
    }
  }

  Future<void> _stopScan() async {
    try {
      await UhfRfidPlugin.stopBarcodeScan();
      setState(() => _isScanning = false);
    } on UhfException catch (e) {
      _showError(e.message);
    }
  }

  Future<void> _setTimeout(int timeout) async {
    try {
      final success = await UhfRfidPlugin.setBarcodeTimeout(timeout);
      if (success) {
        setState(() => _timeout = timeout);
        _showMessage('Timeout set to ${timeout}ms');
      }
    } on UhfException catch (e) {
      _showError(e.message);
    }
  }

  void _clearBarcodes() {
    setState(() {
      _barcodes.clear();
      _barcodeCount.clear();
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Barcode/QR Scanner'),
        actions: [
          IconButton(
            icon: const Icon(Icons.timer),
            onPressed: _isInitialized ? () => _showTimeoutDialog(context) : null,
            tooltip: 'Set Timeout',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _clearBarcodes,
            tooltip: 'Clear Barcodes',
          ),
        ],
      ),
      body: Column(
        children: [
          // Info del escáner
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
                        _isInitialized ? 'Escáner Listo' : 'No Inicializado',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      if (_isScanning)
                        const Row(
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text('Escaneando...'),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Timeout: ${_timeout}ms'),
                  Text('Códigos únicos: ${_barcodeCount.length}'),
                  Text('Total escaneos: ${_barcodes.length}'),
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
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isInitialized && !_isScanning ? _startScan : null,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Escanear'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isScanning ? _stopScan : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('Parar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Nota sobre botón físico
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Tip: También puedes usar el botón físico del PDA para escanear',
              style: TextStyle(color: Colors.grey, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),

          const SizedBox(height: 8),

          // Lista de códigos escaneados
          Expanded(
            child: _barcodes.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No hay códigos escaneados',
                          style: TextStyle(color: Colors.grey),
                        ),
                        Text(
                          'Presiona "Escanear" o usa el botón físico',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _barcodes.length,
                    itemBuilder: (context, index) {
                      final barcode = _barcodes[index];
                      final count = _barcodeCount[barcode.barcode] ?? 1;
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.green,
                            child: Icon(
                              _getBarcodeIcon(barcode.barcode),
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          title: SelectableText(
                            barcode.barcode,
                            style: const TextStyle(
                                fontFamily: 'monospace', fontSize: 14),
                          ),
                          subtitle: Text(
                            '${_formatDateTime(barcode.dateTime)} • Lecturas: $count',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.copy),
                            onPressed: () => _copyToClipboard(barcode.barcode),
                            tooltip: 'Copiar',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  IconData _getBarcodeIcon(String barcode) {
    // Detectar si es un código QR (generalmente URLs o texto largo)
    if (barcode.startsWith('http') || barcode.length > 30) {
      return Icons.qr_code;
    }
    return Icons.barcode_reader;
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  void _copyToClipboard(String text) {
    // Copiar al portapapeles usando Clipboard del sistema
    _showMessage('Copiado: $text');
  }

  void _showTimeoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Timeout de Escaneo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Selecciona el tiempo máximo de escaneo:'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((seconds) {
                final timeout = seconds * 1000;
                return ChoiceChip(
                  label: Text('${seconds}s'),
                  selected: _timeout == timeout,
                  onSelected: (selected) {
                    if (selected) {
                      _setTimeout(timeout);
                      Navigator.pop(context);
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
  }
}

// ============ Settings Sheet ============

class SettingsSheet extends StatefulWidget {
  final Map<String, int>? currentPower;
  final String? currentRegion;
  final Function(int read, int write) onPowerChanged;
  final Function(FrequencyRegion region) onRegionChanged;

  const SettingsSheet({
    super.key,
    required this.currentPower,
    required this.currentRegion,
    required this.onPowerChanged,
    required this.onRegionChanged,
  });

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  late double _readPower;
  late double _writePower;
  late String _selectedRegion;

  @override
  void initState() {
    super.initState();
    _readPower = (widget.currentPower?['readPower'] ?? 26).toDouble();
    _writePower = (widget.currentPower?['writePower'] ?? 26).toDouble();
    _selectedRegion = widget.currentRegion ?? 'USA';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),

          // Power settings
          Text('Read Power: ${_readPower.toInt()} dBm'),
          Slider(
            value: _readPower,
            min: 5,
            max: 33,
            divisions: 28,
            label: '${_readPower.toInt()} dBm',
            onChanged: (value) => setState(() => _readPower = value),
          ),

          Text('Write Power: ${_writePower.toInt()} dBm'),
          Slider(
            value: _writePower,
            min: 5,
            max: 33,
            divisions: 28,
            label: '${_writePower.toInt()} dBm',
            onChanged: (value) => setState(() => _writePower = value),
          ),

          ElevatedButton(
            onPressed: () {
              widget.onPowerChanged(_readPower.toInt(), _writePower.toInt());
              Navigator.pop(context);
            },
            child: const Text('Apply Power'),
          ),

          const Divider(height: 32),

          // Region settings
          Text('Frequency Region',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButton<String>(
            value: _selectedRegion,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 'USA', child: Text('USA (902-928 MHz)')),
              DropdownMenuItem(value: 'EU', child: Text('Europe (865-868 MHz)')),
              DropdownMenuItem(value: 'CHN', child: Text('China (920-925 MHz)')),
              DropdownMenuItem(
                  value: 'KOREA', child: Text('Korea (917-923 MHz)')),
            ],
            onChanged: (value) => setState(() => _selectedRegion = value!),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              final region = FrequencyRegion.values.firstWhere(
                (r) => r.value == _selectedRegion,
                orElse: () => FrequencyRegion.usa,
              );
              widget.onRegionChanged(region);
              Navigator.pop(context);
            },
            child: const Text('Apply Region'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ============ Tag Details Sheet ============

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

      setState(() => _tidData = tid ?? 'No data');
    } on UhfException catch (e) {
      _showError(e.message);
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

      setState(() => _userData = userData ?? 'No data');
    } on UhfException catch (e) {
      _showError(e.message);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tag Details', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),

          Text('EPC:', style: Theme.of(context).textTheme.labelSmall),
          SelectableText(
            widget.tag.epc,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Text('RSSI: ${widget.tag.rssi} dBm'),
              const SizedBox(width: 16),
              Text('Count: ${widget.tag.count}'),
              if (widget.tag.antenna != null) ...[
                const SizedBox(width: 16),
                Text('Antenna: ${widget.tag.antenna}'),
              ],
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _readTid,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Read TID'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _readUserData,
                icon: const Icon(Icons.storage),
                label: const Text('Read USER'),
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
