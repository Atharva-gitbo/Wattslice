import 'package:flutter/material.dart';
import '../models/device.dart';
import '../services/esp_tcp_service.dart';

// Mirrors ESP32 SystemState enum
enum SystemState { normal, peakAlert, ecoMode }

class AppState extends ChangeNotifier {
  final EspTcpService tcpService;

  ElectricityPeriod currentPeriod = ElectricityPeriod.shoulder;
  double currentRate = 0.40;
  DateTime nextPeriodTime = DateTime.now().add(const Duration(hours: 4));

  SystemState systemState = SystemState.normal;

  // Devices match ESP32 apps[]: apps[0]=Mini Fan, apps[1]=Speaker, apps[2]=Light
  // with R4 device keys: fan, buzzer, led
  List<Device> devices = [
    Device(
      id: 'fan',
      name: 'Mini Fan',
      location: 'Desktop',
      icon: Icons.toys,
      r4Key: 'fan',
      state: DeviceState.on,
      currentPeriod: ElectricityPeriod.peak,
      powerWatts: 12.5,
      energyKwh: 0.3,
      costToday: 0.14,
      runtimeMinutes: 60,
    ),
    Device(
      id: 'buzzer',
      name: 'Speaker',
      location: 'Desktop',
      icon: Icons.volume_up,
      r4Key: 'buzzer',
      state: DeviceState.on,
      currentPeriod: ElectricityPeriod.shoulder,
      powerWatts: 5.0,
      energyKwh: 0.12,
      costToday: 0.05,
      runtimeMinutes: 60,
    ),
    Device(
      id: 'led',
      name: 'Light',
      location: 'Desktop',
      icon: Icons.lightbulb_outline,
      r4Key: 'led',
      state: DeviceState.on,
      currentPeriod: ElectricityPeriod.shoulder,
      powerWatts: 8.2,
      energyKwh: 0.2,
      costToday: 0.08,
      runtimeMinutes: 60,
    ),
  ];

  AppState({required this.tcpService}) {
    tcpService.onDataReceived = _handleTcpData;
    tcpService.addListener(() => notifyListeners());
    tcpService.connect();
  }

  void _handleTcpData(Map<String, dynamic> data) {
    // Only update live power readings — device states are managed by user actions.
    // Updating states from R4 data causes snap-back because R4 sends stale mode
    // before it has processed the latest command.
    for (final device in devices) {
      if (data.containsKey(device.r4Key)) {
        final p = data[device.r4Key]['p'];
        if (p != null) device.powerMw = (p as num).toDouble();
      }
    }

    notifyListeners();
  }

  void toggleDevice(int index, bool on) {
    if (index < 0 || index >= devices.length) return;
    devices[index].state = on ? DeviceState.on : DeviceState.off;
    tcpService.setDevice(index, on);
    notifyListeners();
  }

  void setMode(String mode) {
    tcpService.setMode(mode);
    switch (mode) {
      case 'eco':
      case 'smart_delay':
        systemState = SystemState.ecoMode;
        for (final d in devices) {
          if (d.state == DeviceState.on) d.state = DeviceState.eco;
        }
        break;
      default:
        systemState = SystemState.normal;
        for (final d in devices) {
          if (d.state == DeviceState.eco) d.state = DeviceState.on;
        }
    }
    notifyListeners();
  }

  void setDeviceEco(int index) {
    if (index < 0 || index >= devices.length) return;
    devices[index].state = DeviceState.eco;
    tcpService.setDevice(index, true);
    tcpService.setMode('eco');
    systemState = SystemState.ecoMode;
    notifyListeners();
  }

  void cancelEcoDevice(int index) {
    if (index < 0 || index >= devices.length) return;
    devices[index].state = DeviceState.on;
    tcpService.setDevice(index, true);
    final anyEcoLeft = devices.where((d) => d.state == DeviceState.eco).isNotEmpty;
    if (!anyEcoLeft) {
      tcpService.setMode('normal');
      systemState = SystemState.normal;
    }
    notifyListeners();
  }

  void scheduleDevice(String deviceId, String time, String mode) {
    final idx = devices.indexWhere((d) => d.id == deviceId);
    if (idx == -1) return;
    devices[idx].state = DeviceState.delayed;
    devices[idx].scheduledTime = time;
    tcpService.setDevice(idx, false);
    tcpService.setMode('smart_delay');
    notifyListeners();
  }

  void updateDeviceSettings(String deviceId, bool ecoLogic, bool autoQueue, bool lowestRate) {
    final idx = devices.indexWhere((d) => d.id == deviceId);
    if (idx == -1) return;
    devices[idx].ecoLogicMode = ecoLogic;
    devices[idx].autoQueue = autoQueue;
    devices[idx].lowestRateOnly = lowestRate;
    notifyListeners();
  }
}
