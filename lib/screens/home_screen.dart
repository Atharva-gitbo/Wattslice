import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_state.dart';
import '../models/device.dart';
import '../widgets/rate_card.dart';
import '../widgets/device_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    final tcp = appState.tcpService;
    final todayStr = DateFormat('MMM d').format(DateTime.now());

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text(
                        'WattSlice',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        tcp.isConnected ? Icons.wifi : Icons.wifi_off,
                        color: tcp.isConnected ? Colors.blueAccent : Colors.grey,
                        size: 20,
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Today', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text(
                        todayStr,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Current Rate Card
              RateCard(
                period: appState.currentPeriod,
                rate: appState.currentRate,
                nextPeriodTime: appState.nextPeriodTime,
              ),
              const SizedBox(height: 16),

              // Live Usage Card
              _buildLiveUsageCard(appState),
              const SizedBox(height: 32),

              // YOUR LIST section
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text(
                    'YOUR LIST',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Icon(Icons.play_arrow, size: 16),
                ],
              ),
              const SizedBox(height: 16),

              // First device preview
              if (appState.devices.isNotEmpty)
                DeviceCard(device: appState.devices.first),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveUsageCard(AppState appState) {
    final tcp = appState.tcpService;
    final liveMw = tcp.fanPowerMw + tcp.buzzerPowerMw + tcp.ledPowerMw;
    final isLive = tcp.isConnected && liveMw > 0;
    final displayW = isLive
        ? liveMw / 1000.0
        : appState.devices
            .where((d) => d.state == DeviceState.on || d.state == DeviceState.eco)
            .fold(0.0, (sum, d) => sum + d.powerWatts);
    final bulbs = (displayW / 100).round().clamp(1, 99);
    final maxW = 100.0;
    final progress = (displayW / maxW).clamp(0.0, 1.0);

    final totalSpentToday = appState.devices
        .fold(0.0, (sum, d) => sum + d.costToday);
    final savedToday = appState.devices
        .where((d) => d.state == DeviceState.eco)
        .fold(0.0, (sum, d) => sum + d.costToday * 0.2);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'LIVE USAGE',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isLive
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.grey.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isLive ? Icons.sensors : Icons.sensors_off,
                  size: 16,
                  color: isLive ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                displayW >= 1
                    ? displayW.toStringAsFixed(0)
                    : (displayW * 1000).toStringAsFixed(0),
                style: const TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                displayW >= 1 ? 'W' : 'mW',
                style: const TextStyle(
                  fontSize: 22,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5E2BFF)),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    'Like ~$bulbs bulb${bulbs == 1 ? '' : 's'}',
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    '\$${totalSpentToday.toStringAsFixed(2)} spent',
                    style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                        fontWeight: FontWeight.w500),
                  ),
                  if (savedToday > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.savings_outlined,
                              size: 13, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            'Saved \$${savedToday.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
