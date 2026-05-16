import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:developer';
import 'package:flutter/foundation.dart';

class EspTcpService extends ChangeNotifier {
  String espIp;
  final int espPort;

  Socket? _socket;
  bool _isConnected = false;
  String _statusMessage = 'Disconnected';
  Timer? _reconnectTimer;
  String _rxBuffer = '';

  // Live R4 power readings (mW from INA226)
  double fanPowerMw = 0.0;
  double buzzerPowerMw = 0.0;
  double ledPowerMw = 0.0;

  // ESP32 system mode echoed back in R4 data
  String espMode = 'normal';

  // Callback for AppState to process incoming data
  Function(Map<String, dynamic>)? onDataReceived;

  EspTcpService({this.espIp = 'wattslice.local', this.espPort = 8081});

  bool get isConnected => _isConnected;
  String get statusMessage => _statusMessage;

  Future<void> connect() async {
    if (_isConnected) return;
    _reconnectTimer?.cancel();

    try {
      _statusMessage = 'Connecting...';
      notifyListeners();
      log('TCP: Connecting to $espIp:$espPort');

      _socket = await Socket.connect(
        espIp,
        espPort,
        timeout: const Duration(seconds: 5),
      );

      _isConnected = true;
      _statusMessage = 'Connected to ESP32';
      log('TCP: Connected');
      notifyListeners();

      _socket!.cast<List<int>>().transform(utf8.decoder).listen(
        _onData,
        onError: (Object e) {
          log('TCP error: $e');
          _onDisconnected();
        },
        onDone: _onDisconnected,
        cancelOnError: true,
      );
    } catch (e) {
      log('TCP: Connect failed: $e');
      _statusMessage = 'Offline — retrying...';
      _isConnected = false;
      notifyListeners();
      _scheduleReconnect();
    }
  }

  void _onData(String chunk) {
    _rxBuffer += chunk;
    while (_rxBuffer.contains('\n')) {
      final idx = _rxBuffer.indexOf('\n');
      final line = _rxBuffer.substring(0, idx).trim();
      _rxBuffer = _rxBuffer.substring(idx + 1);
      if (line.isNotEmpty) _processLine(line);
    }
  }

  void _processLine(String line) {
    log('TCP Rx: $line');
    try {
      final doc = json.decode(line) as Map<String, dynamic>;
      if (doc.containsKey('mode')) espMode = doc['mode'] as String? ?? espMode;
      if (doc.containsKey('fan'))    fanPowerMw    = (doc['fan']['p']    as num?)?.toDouble() ?? fanPowerMw;
      if (doc.containsKey('buzzer')) buzzerPowerMw = (doc['buzzer']['p'] as num?)?.toDouble() ?? buzzerPowerMw;
      if (doc.containsKey('led'))    ledPowerMw    = (doc['led']['p']    as num?)?.toDouble() ?? ledPowerMw;
      onDataReceived?.call(doc);
      notifyListeners();
    } catch (e) {
      log('TCP: JSON parse error: $e  line=$line');
    }
  }

  void _onDisconnected() {
    log('TCP: Disconnected');
    _socket?.destroy();
    _socket = null;
    _isConnected = false;
    _statusMessage = 'Disconnected';
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), connect);
  }

  // Send {"cmd":"...","value":"..."}\n to the ESP32
  void sendCommand(String cmd, String value) {
    if (!_isConnected || _socket == null) {
      log('TCP: Cannot send, not connected');
      return;
    }
    final msg = json.encode({'cmd': cmd, 'value': value}) + '\n';
    log('TCP Tx: $msg');
    _socket!.write(msg);
  }

  // Toggle a device by index (0=fan, 1=buzzer, 2=led)
  void setDevice(int index, bool on) {
    const keys = ['fan', 'buzzer', 'led'];
    if (index < 0 || index >= keys.length) return;
    sendCommand(keys[index], on ? 'on' : 'off');
  }

  // Send a mode command: 'eco', 'smart_delay', or 'normal'
  void setMode(String mode) {
    sendCommand('mode', mode);
    espMode = mode;
    notifyListeners();
  }

  void updateEspIp(String newIp) {
    espIp = newIp;
    _onDisconnected();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _socket?.destroy();
    super.dispose();
  }
}
