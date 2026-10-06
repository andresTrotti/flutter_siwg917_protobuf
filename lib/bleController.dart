import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

class Si917BleController {
  final flutterReactiveBle = FlutterReactiveBle();
  StreamSubscription<ConnectionStateUpdate>? _connection;

  // Reemplaza con los UUIDs reales de tu SiWG917
  final Uuid serviceUuid = Uuid.parse("6a4e3300-667b-11e3-949a-0800200c9a66");
  final Uuid protectedCharUuid = Uuid.parse("6a4e3304-667b-11e3-949a-0800200c9a66");

  String? _connectedDeviceId;

  // 1. Escanear y conectar
  void connectToSi917(String deviceId) {
    _connectedDeviceId = deviceId;

    _connection = flutterReactiveBle.connectToDevice(
      id: deviceId,
      connectionTimeout: const Duration(seconds: 5),
    ).listen((connectionState) {
      print("Estado de conexión: ${connectionState.connectionState}");

      if (connectionState.connectionState == DeviceConnectionState.connected) {
        // Una vez conectado, forzamos el emparejamiento
        _triggerPairingProcess();
      }
    }, onError: (Object error) {
      print("Error de conexión: $error");
    });
  }

  // 2. Forzar el cuadro de diálogo del Passkey
  Future<void> _triggerPairingProcess() async {
    if (_connectedDeviceId == null) return;

    final protectedCharacteristic = QualifiedCharacteristic(
      serviceId: serviceUuid,
      characteristicId: protectedCharUuid,
      deviceId: _connectedDeviceId!,
    );

    try {
      print("Intentando leer/escribir característica protegida...");
      // Al intentar leer esta característica encriptada,
      // el OS mostrará el popup nativo pidiendo el PIN.
      final response = await flutterReactiveBle.readCharacteristic(protectedCharacteristic);

      print("¡Emparejamiento exitoso! Datos leídos: $response");

      // A partir de aquí, el dispositivo está "Bonded" y puedes suscribirte
      // a notificaciones o enviar tus comandos Protobuf libremente.
      _subscribeToNotifications();

    } catch (e) {
      // Si el usuario cancela el diálogo del PIN o falla, caerá aquí
      print("Fallo en el emparejamiento o lectura: $e");
    }
  }

  // 3. Suscribirse (Como lo harías normalmente)
  void _subscribeToNotifications() {
    // Aquí iría tu lógica de listen() a la característica de notificaciones
  }

  void disconnect() {
    _connection?.cancel();
    _connectedDeviceId = null;
  }
}