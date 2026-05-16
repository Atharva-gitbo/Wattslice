import 'package:flutter/material.dart';

// Mirrors ESP32 apps[].state: 0=off, 1=on, 2=eco, 3=delayed (smart delay)
enum DeviceState { off, on, eco, delayed }

enum ElectricityPeriod { peak, shoulder, offPeak }

class Device {
  final String id;
  final String name;
  final String location;
  final IconData icon;
  final String r4Key; // 'fan', 'buzzer', 'led' — matches ESP32 R4_DEVICE[]

  DeviceState state;
  ElectricityPeriod currentPeriod;
  double powerWatts;  // simulated product-level power (shown in UI)
  double powerMw;     // live INA226 reading from R4 (mW)
  double energyKwh;
  double costToday;
  int runtimeMinutes;

  bool ecoLogicMode;
  bool autoQueue;
  bool lowestRateOnly;
  String? scheduledTime;

  Device({
    required this.id,
    required this.name,
    required this.location,
    required this.icon,
    required this.r4Key,
    this.state = DeviceState.on,
    this.currentPeriod = ElectricityPeriod.shoulder,
    this.powerWatts = 0.0,
    this.powerMw = 0.0,
    this.energyKwh = 0.0,
    this.costToday = 0.0,
    this.runtimeMinutes = 0,
    this.ecoLogicMode = false,
    this.autoQueue = false,
    this.lowestRateOnly = false,
    this.scheduledTime,
  });
}
