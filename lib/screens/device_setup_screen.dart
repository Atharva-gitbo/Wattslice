import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/esp_tcp_service.dart';
import '../main.dart';

class DeviceSetupScreen extends StatefulWidget {
  const DeviceSetupScreen({super.key});

  @override
  State<DeviceSetupScreen> createState() => _DeviceSetupScreenState();
}

class _DeviceSetupScreenState extends State<DeviceSetupScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _ipController =
      TextEditingController(text: '');

  _SetupState _state = _SetupState.idle;
  String? _errorMessage;
  Timer? _timeoutTimer;

  late AnimationController _pulseController;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    _timeoutTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _connect() {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      setState(() => _errorMessage = 'Please enter the device IP address.');
      return;
    }

    setState(() {
      _state = _SetupState.connecting;
      _errorMessage = null;
    });

    final tcp = Provider.of<EspTcpService>(context, listen: false);
    tcp.updateEspIp(ip);

    // Listen for connection result
    void listener() {
      if (!mounted) return;
      if (tcp.isConnected) {
        _timeoutTimer?.cancel();
        tcp.removeListener(listener);
        setState(() => _state = _SetupState.connected);
        Future.delayed(const Duration(seconds: 2), _enterApp);
      }
    }

    tcp.addListener(listener);

    // Timeout after 8 seconds
    _timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      tcp.removeListener(listener);
      if (!tcp.isConnected) {
        setState(() {
          _state = _SetupState.failed;
          _errorMessage =
              'Could not reach the device.\nMake sure you\'re on the same Wi‑Fi as the ESP32 and the board is powered on.';
        });
      }
    });
  }

  void _enterApp() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
    );
  }

  void _retry() {
    setState(() {
      _state = _SetupState.idle;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),

              // WattSlice wordmark
              const Text(
                'WattSlice',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 40),

              // Main content (animated transitions)
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_state == _SetupState.connecting) return _buildConnecting();
    if (_state == _SetupState.connected) return _buildConnected();
    if (_state == _SetupState.failed) return _buildFailed();
    return _buildIdle();
  }

  // ── Idle ──────────────────────────────────────────────────────────────────

  Widget _buildIdle() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero icon
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF5E2BFF).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(
            Icons.router_outlined,
            color: Color(0xFF5E2BFF),
            size: 36,
          ),
        ),
        const SizedBox(height: 28),

        const Text(
          'Connect to your\nWattSlice Hub',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            height: 1.15,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Make sure your phone is on the same Wi‑Fi network as the ESP32 board, then enter its IP address below.',
          style: TextStyle(
              color: Colors.grey.shade600, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 36),

        // Wi-Fi reminder chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.blue.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.wifi, color: Colors.blueAccent, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Connect your phone to "AtharvaHotspot" — same network as the ESP32',
                  style: TextStyle(
                      color: Colors.blue.shade700,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // IP field
        const Text(
          'Device IP Address',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ipController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: '192.168.x.x',
            prefixIcon: const Icon(Icons.lan_outlined, color: Colors.grey),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:
                  const BorderSide(color: Color(0xFF5E2BFF), width: 2),
            ),
            errorText: _errorMessage,
          ),
        ),
        const Spacer(),

        // Connect button
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _connect,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF5E2BFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              elevation: 0,
            ),
            child: const Text(
              'Connect to Device',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _enterApp,
            child: Text(
              'Skip for now',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Connecting ────────────────────────────────────────────────────────────

  Widget _buildConnecting() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ScaleTransition(
          scale: _pulse,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF5E2BFF).withValues(alpha: 0.12),
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
          'Connecting…',
          style: TextStyle(
              fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5),
        ),
        const SizedBox(height: 10),
        Text(
          'Reaching ${_ipController.text.trim()}:8081',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
        ),
        const SizedBox(height: 40),
        const LinearProgressIndicator(
          color: Color(0xFF5E2BFF),
          backgroundColor: Color(0xFFE8E2FF),
        ),
      ],
    );
  }

  // ── Connected ─────────────────────────────────────────────────────────────

  Widget _buildConnected() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_outline_rounded,
            color: Colors.green,
            size: 60,
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'Connected!',
          style: TextStyle(
              fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.5),
        ),
        const SizedBox(height: 10),
        Text(
          'WattSlice Hub is online.\nTaking you to the app…',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 15, height: 1.5),
        ),
      ],
    );
  }

  // ── Failed ────────────────────────────────────────────────────────────────

  Widget _buildFailed() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          'Could not connect',
          style: TextStyle(
              fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -0.5),
        ),
        const SizedBox(height: 14),
        Text(
          _errorMessage ?? '',
          style: TextStyle(
              color: Colors.grey.shade600, fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 28),

        // Checklist of things to verify
        ..._hints.map((h) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.arrow_right_rounded,
                      color: Colors.grey.shade400, size: 20),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(h,
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 14)),
                  ),
                ],
              ),
            )),

        const Spacer(),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _retry,
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
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: _enterApp,
            child: Text('Continue without device',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  static const _hints = [
    'Your phone is on "AtharvaHotspot" (same network as ESP32)',
    'ESP32 board is powered on and running',
    'Double-check the IP shown on the Serial Monitor',
  ];
}

enum _SetupState { idle, connecting, connected, failed }
