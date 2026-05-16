import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/esp_tcp_service.dart';
import '../main.dart';

class ConnectingScreen extends StatefulWidget {
  const ConnectingScreen({super.key});

  @override
  State<ConnectingScreen> createState() => _ConnectingScreenState();
}

class _ConnectingScreenState extends State<ConnectingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scale;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _scale = Tween(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );

    _startSearch();
  }

  void _startSearch() {
    setState(() => _failed = false);
    final tcp = Provider.of<EspTcpService>(context, listen: false);

    // Watch for connection success
    void listener() {
      if (!mounted) return;
      if (tcp.isConnected) {
        tcp.removeListener(listener);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
        );
      }
    }

    tcp.addListener(listener);
    tcp.connect();

    // After 6s give up and show instructions
    Future.delayed(const Duration(seconds: 6), () {
      if (!mounted) return;
      tcp.removeListener(listener);
      if (!tcp.isConnected) setState(() => _failed = true);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              const Text(
                'WattSlice',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              Expanded(
                child: _failed ? _buildFailed() : _buildSearching(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearching() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ScaleTransition(
          scale: _scale,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF5E2BFF).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.wifi_find_outlined,
              color: Color(0xFF5E2BFF),
              size: 52,
            ),
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'Looking for\nWattSlice Hub…',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Make sure your device is connected to\nthe same WiFi as the ESP32.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 14, height: 1.5),
        ),
        const SizedBox(height: 32),
        const LinearProgressIndicator(
          color: Color(0xFF5E2BFF),
          backgroundColor: Color(0xFFE8E2FF),
        ),
      ],
    );
  }

  Widget _buildFailed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(Icons.wifi_off_rounded,
              color: Colors.redAccent, size: 36),
        ),
        const SizedBox(height: 28),
        const Text(
          "Couldn't find\nthe Hub",
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 20),

        // Step 1
        _buildStep(
          '1',
          'Connect to ESP32_AP',
          'Go to WiFi settings → select "ESP32_AP"\nPassword: 12345678',
          Icons.wifi,
          Colors.blue,
        ),
        const SizedBox(height: 14),

        // Step 2
        _buildStep(
          '2',
          'Come back here',
          'Return to this app — it connects automatically',
          Icons.check_circle_outline,
          Colors.green,
        ),

        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _startSearch,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5E2BFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              elevation: 0,
            ),
            child: const Text('Try Again',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                  builder: (_) => const MainNavigationScreen()),
            ),
            child: Text('Skip — use without hardware',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildStep(String number, String title, String body,
      IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
