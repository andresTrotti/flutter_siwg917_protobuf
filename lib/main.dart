import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter BLE Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Escáner Bluetooth BLE'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

//changes on developer-2 

class _MyHomePageState extends State<MyHomePage> {
  // Instancia de la librería BLE y del controlador Si917
  final FlutterReactiveBle _ble = FlutterReactiveBle();
  final Si917BleController _si917Controller = Si917BleController();

  // Lista para almacenar los dispositivos detectados
  final List<DiscoveredDevice> _devices = [];

  // Suscripción para escuchar el stream de escaneo
  StreamSubscription? _scanStream;

  // Estado para saber si estamos escaneando
  bool _isScanning = false;

  // Método para lanzar o detener el proceso de escaneo con validación de permisos

  Future<void> _toggleScan() async {
    if (_isScanning) {
      _scanStream?.cancel();
      setState(() {
        _isScanning = false;
      });
    } else {
      // 1. Validar permisos solo si estamos en Android
      if (Platform.isAndroid) {
        Map<Permission, PermissionStatus> statuses = await [
          Permission.location,
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
        ].request();

        if (statuses[Permission.bluetoothScan] != PermissionStatus.granted ||
            statuses[Permission.bluetoothConnect] != PermissionStatus.granted) {
          debugPrint("Permisos de Bluetooth denegados en Android.");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Se requieren permisos de Bluetooth para buscar dispositivos.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }
      // En iOS, el sistema operativo mostrará automáticamente el aviso
      // configurado en tu Info.plist al momento de ejecutar flutter_reactive_ble.scanForDevices()

      // 2. Iniciamos el escaneo
      setState(() {
        _devices.clear();
        _isScanning = true;
      });

      _scanStream = _ble.scanForDevices(withServices: []).listen((device) {
        if (!_devices.any((d) => d.id == device.id)) {
          setState(() {
            _devices.add(device);
          });
        }
      }, onError: (error) {
        debugPrint("Error al escanear: $error");
        setState(() {
          _isScanning = false;
        });
      });
    }
  }

  @override
  void dispose() {
    _scanStream?.cancel();
    _si917Controller.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          // Botón superior para controlar el escaneo
          ElevatedButton.icon(
            onPressed: _toggleScan,
            icon: Icon(_isScanning ? Icons.stop : Icons.search),
            label: Text(_isScanning ? 'Detener Escaneo' : 'Iniciar Escaneo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isScanning ? Colors.red : Colors.deepPurple,
              foregroundColor: Colors.white,
            ),
          ),
          const Divider(),
          // Lista de dispositivos encontrados en tiempo real
          Expanded(
            child: _devices.isEmpty
                ? Center(
              child: Text(
                _isScanning ? 'Buscando dispositivos...' : 'Presiona el botón para buscar',
                style: const TextStyle(color: Colors.grey),
              ),
            )
                : ListView.builder(
              itemCount: _devices.length,
              itemBuilder: (context, index) {
                final device = _devices[index];
                final name = device.name.isNotEmpty ? device.name : 'Dispositivo Desconocido';

                return ListTile(
                  leading: const Icon(Icons.bluetooth, color: Colors.deepPurple),
                  title: Text(name),
                  subtitle: Text('ID: ${device.id}\nRSSI: ${device.rssi} dBm'),
                  isThreeLine: true,
                  // Al hacer tap sobre un dispositivo, detenemos el escaneo y nos conectamos
                  onTap: () {
                    if (_isScanning) {
                      _scanStream?.cancel();
                      setState(() => _isScanning = false);
                    }

                    // Disparamos la conexión hacia el Si917
                    debugPrint("Intentando conectar a: ${device.id}");
                    _si917Controller.connectToSi917(device.id);

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Conectando a $name...')),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      // Botón flotante para alternar el escaneo rápidamente
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleScan,
        tooltip: _isScanning ? 'Detener' : 'Escanear',
        backgroundColor: _isScanning ? Colors.red : Colors.deepPurple,
        child: Icon(_isScanning ? Icons.stop : Icons.search, color: Colors.white),
      ),
    );
  }
}

/// Controlador para la gestión específica del dispositivo Si917 y sus características seguras
class Si917BleController {
  final flutterReactiveBle = FlutterReactiveBle();
  StreamSubscription<ConnectionStateUpdate>? _connection;

  final Uuid serviceUuid = Uuid.parse("6a4e3300-667b-11e3-949a-0800200c9a66");
  final Uuid protectedCharUuid = Uuid.parse("6a4e3304-667b-11e3-949a-0800200c9a66");

  String? _connectedDeviceId;
  bool _intentionalDisconnect = false; // Bandera para saber si fue a propósito

  // 1. Conectar e implementar reconexión automática
  void connectToSi917(String deviceId) {
    _connectedDeviceId = deviceId;
    _intentionalDisconnect = false;

    _connection?.cancel();
    _connection = flutterReactiveBle.connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 10),
    ).listen((connectionState) {
      debugPrint("Estado de conexión: ${connectionState.connectionState}");

      if (connectionState.connectionState == DeviceConnectionState.connected) {
        debugPrint("¡Conectado exitosamente!");
        _triggerPairingProcess();
      }
      else if (connectionState.connectionState == DeviceConnectionState.disconnected) {
        debugPrint("Se perdió la conexión con el Si917.");

        // Si no fue una desconexión intencional (ej. apagaste el bluetooth o se alejó), intentamos reconectar
        if (!_intentionalDisconnect && _connectedDeviceId != null) {
          _attemptReconnection(_connectedDeviceId!);
        }
      }
    }, onError: (Object error) {
      debugPrint("Error de conexión: $error");
      if (!_intentionalDisconnect && _connectedDeviceId != null) {
        _attemptReconnection(_connectedDeviceId!);
      }
    });
  }

  // 2. Lógica de reintento automático
  void _attemptReconnection(String deviceId) {
    debugPrint("Intentando reconectar en 7 segundos...");
    Future.delayed(const Duration(seconds: 7), () {
      if (!_intentionalDisconnect) {
        connectToSi917(deviceId);
      }
    });
  }

  Future<void> _triggerPairingProcess() async {
    if (_connectedDeviceId == null) return;

    try {
      debugPrint("Solicitando descubrimiento para asegurar el vínculo...");
      await flutterReactiveBle.discoverServices(_connectedDeviceId!);
      debugPrint("¡Emparejamiento y servicios listos!");
    } catch (e) {
      debugPrint("Fallo en el descubrimiento: $e");
    }
  }

  void disconnect() {
    _intentionalDisconnect = true; // Marcamos que el usuario quiso desconectarse
    _connection?.cancel();
    _connectedDeviceId = null;
    debugPrint("Desconexión manual realizada.");
  }
}