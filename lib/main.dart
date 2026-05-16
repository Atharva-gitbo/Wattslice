import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

import 'providers/app_state.dart';
import 'services/esp_tcp_service.dart';
import 'screens/home_screen.dart';
import 'screens/devices_screen.dart';
import 'screens/weekly_insights_screen.dart';
import 'screens/connect_provider_screen.dart';
import 'screens/connecting_screen.dart';

void main() {
  runApp(const WattSliceApp());
}

class WattSliceApp extends StatelessWidget {
  const WattSliceApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => EspTcpService()),
        ChangeNotifierProxyProvider<EspTcpService, AppState>(
          create: (context) => AppState(tcpService: Provider.of<EspTcpService>(context, listen: false)),
          update: (context, tcpService, previous) => previous ?? AppState(tcpService: tcpService),
        ),
      ],
      child: MaterialApp(
        title: 'WattSlice',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xFFF8F9FA),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF5E2BFF),
            primary: const Color(0xFF5E2BFF),
            background: const Color(0xFFF8F9FA),
            surface: Colors.white,
          ),
          textTheme: GoogleFonts.interTextTheme(
            Theme.of(context).textTheme,
          ),
          navigationBarTheme: NavigationBarThemeData(
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const TextStyle(
                  color: Color(0xFF5E2BFF),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                );
              }
              return TextStyle(color: Colors.grey.shade500, fontSize: 12);
            }),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF8F9FA),
            elevation: 0,
            iconTheme: IconThemeData(color: Colors.black),
            titleTextStyle: TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        home: const ConnectingScreen(),
      ),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({Key? key}) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const HomeScreen(),
    const DevicesScreen(),
    const WeeklyInsightsScreen(),
    const ConnectProviderScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        backgroundColor: Colors.white,
        elevation: 2,
        shadowColor: Colors.black12,
        indicatorColor: const Color(0xFF5E2BFF).withValues(alpha: 0.1),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: Color(0xFF5E2BFF)),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.bolt_outlined),
            selectedIcon: Icon(Icons.bolt, color: Color(0xFF5E2BFF)),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights, color: Color(0xFF5E2BFF)),
            label: 'Insights',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings, color: Color(0xFF5E2BFF)),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
