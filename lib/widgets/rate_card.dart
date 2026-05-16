import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/device.dart';

class RateCard extends StatelessWidget {
  final ElectricityPeriod period;
  final double rate;
  final DateTime nextPeriodTime;

  const RateCard({
    super.key,
    required this.period,
    required this.rate,
    required this.nextPeriodTime,
  });

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('h:mm a').format(nextPeriodTime);
    final nextPeriodText = period == ElectricityPeriod.shoulder
        ? 'Off-Peak'
        : (period == ElectricityPeriod.offPeak ? 'Peak' : 'Shoulder');

    if (period == ElectricityPeriod.peak) {
      return _buildPeakCard(timeStr);
    }
    return _buildNormalCard(timeStr, nextPeriodText);
  }

  Widget _buildPeakCard(String timeStr) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CURRENT PERIOD',
                style: TextStyle(
                  color: Colors.red.shade400,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              Icon(Icons.warning_amber_rounded, color: Colors.red.shade400, size: 22),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Peak',
            style: TextStyle(
              color: Colors.red.shade700,
              fontSize: 42,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Electricity is most expensive right now.\nTry to minimize high-energy use until $timeStr.',
            style: TextStyle(color: Colors.red.shade600, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalCard(String timeStr, String nextPeriod) {
    final Color dotColor =
        period == ElectricityPeriod.offPeak ? Colors.lightGreenAccent : Colors.amber;
    final String periodText =
        period == ElectricityPeriod.offPeak ? 'Off-Peak' : 'Shoulder';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF15192C),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Current Period',
                    style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('Rate', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '\$${rate.toStringAsFixed(1)}',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const Text('/kWh', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            periodText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.schedule, color: Colors.white.withValues(alpha: 0.8), size: 16),
              const SizedBox(width: 8),
              Text(
                'Next: $nextPeriod at $timeStr',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9), fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
