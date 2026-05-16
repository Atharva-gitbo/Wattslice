import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/device.dart';
import '../providers/app_state.dart';
import '../screens/schedule_delay_screen.dart';
import '../screens/device_settings_screen.dart';

class DeviceCard extends StatelessWidget {
  final Device device;

  const DeviceCard({super.key, required this.device});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context, listen: false);
    final idx = appState.devices.indexWhere((d) => d.id == device.id);
    final isOn = device.state == DeviceState.on || device.state == DeviceState.eco;
    final isEco = device.state == DeviceState.eco;

    final Color iconBgColor;
    if (device.state == DeviceState.eco) {
      iconBgColor = Colors.orange;
    } else if (device.state == DeviceState.off) {
      iconBgColor = Colors.grey.shade400;
    } else if (device.currentPeriod == ElectricityPeriod.peak) {
      iconBgColor = Colors.redAccent.shade100;
    } else {
      iconBgColor = const Color(0xFF00C49A);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Row ───────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Device icon
              Stack(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: iconBgColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(device.icon, color: Colors.white, size: 28),
                  ),
                  if (device.currentPeriod == ElectricityPeriod.peak &&
                      device.state == DeviceState.on)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              // Name + badge
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    _buildPeriodBadge(),
                  ],
                ),
              ),
              // Power button + cost
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: idx != -1
                        ? () => appState.toggleDevice(idx, !isOn)
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isOn
                            ? const Color(0xFF5E2BFF)
                            : Colors.grey.shade200,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.power_settings_new,
                        color: isOn ? Colors.white : Colors.grey.shade500,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '\$${device.costToday.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const Text('today',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Stats Row ────────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.power_settings_new,
                  size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                '${device.energyKwh.toStringAsFixed(1)} kWh',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
              ),
              const SizedBox(width: 16),
              Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                _formatRuntime(device.runtimeMinutes),
                style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Usage bar ────────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Usage',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              Text(
                '58%',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 0.58,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5E2BFF)),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 20),

          // ── Eco Mode toggle ──────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.eco_outlined,
                      size: 18,
                      color: isEco ? Colors.orange : Colors.grey.shade400),
                  const SizedBox(width: 8),
                  Text(
                    'Eco Mode',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color:
                          isEco ? Colors.orange : Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
              Switch(
                value: isEco,
                onChanged: idx != -1
                    ? (val) {
                        if (val) {
                          appState.setDeviceEco(idx);
                        } else {
                          appState.cancelEcoDevice(idx);
                        }
                      }
                    : null,
                activeColor: Colors.orange,
                activeTrackColor: Colors.orange.withValues(alpha: 0.3),
                inactiveThumbColor: Colors.grey.shade400,
                inactiveTrackColor: Colors.grey.shade200,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Action row ───────────────────────────────────────────────────
          if (device.state == DeviceState.delayed)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                'Delayed until ${device.scheduledTime}',
                style: TextStyle(
                    color: Colors.grey.shade800,
                    fontWeight: FontWeight.bold),
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ScheduleDelayScreen(device: device),
                    ),
                  );
                },
                icon: const Icon(Icons.access_time_outlined, size: 18),
                label: const Text(
                  'Smart Delay',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5E2BFF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          const SizedBox(height: 10),

          // ── Settings ─────────────────────────────────────────────────────
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF15192C),
                borderRadius: BorderRadius.circular(14),
              ),
              child: IconButton(
                icon: const Icon(Icons.settings_outlined,
                    color: Colors.white, size: 20),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          DeviceSettingsScreen(device: device),
                    ),
                  );
                },
                padding: const EdgeInsets.all(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodBadge() {
    if (device.state == DeviceState.eco) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          '• Eco Mode',
          style: TextStyle(
            color: Colors.orange,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    final Color bgColor;
    final Color textColor;
    final String text;

    switch (device.currentPeriod) {
      case ElectricityPeriod.peak:
        bgColor = Colors.red.withValues(alpha: 0.1);
        textColor = Colors.red;
        text = '• Peak';
        break;
      case ElectricityPeriod.shoulder:
        bgColor = Colors.orange.withValues(alpha: 0.1);
        textColor = Colors.orange;
        text = '• Shoulder';
        break;
      case ElectricityPeriod.offPeak:
        bgColor = Colors.green.withValues(alpha: 0.1);
        textColor = Colors.green;
        text = '• Off-Peak';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _formatRuntime(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) return '${hours}h ${mins}m';
    return '${mins}m';
  }
}
