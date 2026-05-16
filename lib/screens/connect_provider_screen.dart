import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'syncing_device_screen.dart';

class ConnectProviderScreen extends StatelessWidget {
  const ConnectProviderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final todayStr = DateFormat('MMM d').format(DateTime.now());

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'WattSlice',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Today',
                          style: TextStyle(color: Colors.grey, fontSize: 11)),
                      Text(todayStr,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Connect\nProvider',
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Link your electricity company to sync\nreal-time Time-of-Use rates.',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 15, height: 1.4),
                    ),
                    const SizedBox(height: 24),

                    // Search field
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Search other providers...',
                        hintStyle: TextStyle(color: Colors.grey.shade400),
                        prefixIcon:
                            Icon(Icons.search, color: Colors.grey.shade400),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Provider list
                    Expanded(
                      child: ListView(
                        children: [
                          _buildProviderRow(context, 'AGL'),
                          const SizedBox(height: 12),
                          _buildProviderRow(context, 'Energy\nAustralia'),
                          const SizedBox(height: 12),
                          _buildProviderRow(context, 'ORIGIN'),
                        ],
                      ),
                    ),

                    // Secure footer
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline,
                              size: 14, color: Colors.grey.shade500),
                          const SizedBox(width: 8),
                          Text(
                            'SECURE CONNECTION VIA OPEN ENERGY',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderRow(BuildContext context, String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SyncingDeviceScreen()),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.black87,
              side: BorderSide(color: Colors.grey.shade300),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text(
              'CONNECT',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
