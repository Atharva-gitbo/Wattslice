import 'dart:convert';
import 'dart:io';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService extends ChangeNotifier {
  MqttServerClient? _client;

  // --- MQTT Configuration ---
  final String _host = '801fdf76e1444ab6854668d370533b79.s1.eu.hivemq.cloud';
  final int _port = 8883;
  // TODO: Replace with your actual HiveMQ credentials
  final String _username = 'atharva_ppi'; 
  final String _password = 'Atharva17;';
  final String _clientId = 'wattslice_${DateTime.now().millisecondsSinceEpoch % 100000}';

  // --- Hardware State Variables ---
  bool _isConnected = false;
  String _statusMessage = 'Disconnected';
  
  bool _appliance1 = false;
  bool _appliance2 = false;
  bool _appliance3 = false;
  
  double _voltage1 = 0.0;
  double _voltage2 = 0.0;
  double _voltage3 = 0.0;

  // Callback for AppState compatibility
  Function(Map<String, dynamic>)? onMessageReceived;

  // Getters
  bool get isConnected => _isConnected;
  String get statusMessage => _statusMessage;
  bool get appliance1 => _appliance1;
  bool get appliance2 => _appliance2;
  bool get appliance3 => _appliance3;
  double get voltage1 => _voltage1;
  double get voltage2 => _voltage2;
  double get voltage3 => _voltage3;

  Future<void> connect() async {
    if (_isConnected || (_client?.connectionStatus?.state == MqttConnectionState.connecting)) {
      log('MQTT: Already connected or connecting...');
      return;
    }
    
    _client = MqttServerClient.withPort(_host, _clientId, _port);
    _client!.logging(on: true); // Enabled logging to diagnose issues
    _client!.secure = true;
    _client!.onBadCertificate = (dynamic cert) => true; 
    _client!.setProtocolV311();
    _client!.securityContext = SecurityContext.defaultContext;
    _client!.keepAlivePeriod = 60;
    _client!.onDisconnected = _onDisconnected;
    _client!.onConnected = _onConnected;
    _client!.onSubscribed = _onSubscribed;
    _client!.autoReconnect = true;

    final connMessage = MqttConnectMessage()
        .withClientIdentifier(_clientId)
        .authenticateAs(_username, _password)
        .startClean();

    _client!.connectionMessage = connMessage;

    try {
      log('MQTT: Connecting to $_host...');
      await _client!.connect(_username, _password);
    } catch (e) {
      log('MQTT: Exception: $e');
      _statusMessage = 'Error: $e';
      _disconnect();
      notifyListeners();
    }

    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      _isConnected = true;
      _statusMessage = 'Connected';
      log('MQTT: Connected');
      _subscribeToTopics();
      notifyListeners();
    } else {
      log('MQTT: Connection failed');
      _disconnect();
    }
  }

  void _disconnect() {
    _client?.disconnect();
    _onDisconnected();
  }

  void _onConnected() {
    log('MQTT: Connected to broker');
    _isConnected = true;
    _statusMessage = 'Connected';
    notifyListeners();
  }

  void _onDisconnected() {
    log('MQTT: Disconnected from broker');
    _isConnected = false;
    _statusMessage = 'Disconnected';
    notifyListeners();
  }

  void _onSubscribed(String topic) {
    log('MQTT: Subscribed to $topic');
  }

  void _subscribeToTopics() {
    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      final topics = [
        'energy/esp32_energy_01/appliance/1/state',
        'energy/esp32_energy_01/appliance/2/state',
        'energy/esp32_energy_01/appliance/3/state',
        'energy/esp32_energy_01/sensors/voltage1',
        'energy/esp32_energy_01/sensors/voltage2',
        'energy/esp32_energy_01/sensors/voltage3',
        'energy/esp32_energy_01/optimization/status',
      ];

      for (var topic in topics) {
        _client!.subscribe(topic, MqttQos.atLeastOnce);
      }

      _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> event) {
        final MqttPublishMessage recMess = event[0].payload as MqttPublishMessage;
        final String message = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        final String topic = event[0].topic;

    log('MQTT Rx: $topic -> $message');
    
    // Support legacy JSON messages if they arrive
    try {
      final decoded = json.decode(message);
      if (onMessageReceived != null) {
        onMessageReceived!(decoded);
      }
    } catch (_) {
      // Not a JSON message, ignore
    }

    _handleIncomingMessage(topic, message);
    });
  }
}

  void _handleIncomingMessage(String topic, String message) {
    if (topic.contains('appliance/1/state')) {
      _appliance1 = (message == 'ON');
    } else if (topic.contains('appliance/2/state')) {
      _appliance2 = (message == 'ON');
    } else if (topic.contains('appliance/3/state')) {
      _appliance3 = (message == 'ON');
    } else if (topic.contains('sensors/voltage1')) {
      _voltage1 = double.tryParse(message) ?? _voltage1;
    } else if (topic.contains('sensors/voltage2')) {
      _voltage2 = double.tryParse(message) ?? _voltage2;
    } else if (topic.contains('sensors/voltage3')) {
      _voltage3 = double.tryParse(message) ?? _voltage3;
    } else if (topic.contains('optimization/status')) {
      _statusMessage = message;
    }
    
    notifyListeners();
  }

  void publish(String topic, String message) {
    if (_isConnected && _client != null) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(message);
      
      _client!.publishMessage(
        topic,
        MqttQos.atLeastOnce,
        builder.payload!,
      );
      log('MQTT Tx: $topic -> $message');
    } else {
      log('MQTT: Cannot publish, client disconnected');
    }
  }

  void setAppliance(int applianceNumber, bool turnOn) {
    final topic = 'energy/esp32_energy_01/appliance/$applianceNumber/set';
    final message = turnOn ? 'ON' : 'OFF';
    
    // Optimistically update local state for UI responsiveness
    if (applianceNumber == 1) _appliance1 = turnOn;
    if (applianceNumber == 2) _appliance2 = turnOn;
    if (applianceNumber == 3) _appliance3 = turnOn;
    notifyListeners();

    publish(topic, message);
  }

  void runOptimization() {
    final topic = 'energy/esp32_energy_01/optimization/run';
    publish(topic, 'START');
    _statusMessage = 'Optimization Started...';
    notifyListeners();
  }

  // --- Compatibility Methods for AppState ---

  void scheduleDelay(String deviceId, String startTime, String mode) {
    // For now, just publish to a generic control topic or log
    final payload = {
      "deviceId": deviceId,
      "command": "schedule_delay",
      "startTime": startTime,
      "mode": mode
    };
    publish('energy/esp32_energy_01/control', json.encode(payload));
  }

  void updateSettings(String deviceId, bool ecoLogic, bool autoQueue, bool lowestRateOnly) {
    final payload = {
      "deviceId": deviceId,
      "command": "update_settings",
      "ecoLogic": ecoLogic,
      "autoQueue": autoQueue,
      "lowestRateOnly": lowestRateOnly
    };
    publish('energy/esp32_energy_01/control', json.encode(payload));
  }
}
