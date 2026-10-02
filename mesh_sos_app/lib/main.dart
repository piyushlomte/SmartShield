import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/ble_service.dart';
import 'services/location_service.dart';
import 'services/alert_service.dart';
import 'providers/mesh_provider.dart';
import 'providers/sos_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/smartwatch_provider.dart';

import 'screens/dashboard_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/sos_screen.dart';
import 'screens/map_radar_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/checklist_screen.dart';
import 'widgets/emergency_banner.dart';
import 'services/notification_service.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/ai_safety_service.dart';
import 'widgets/ai_countdown_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Local Notifications
  await NotificationService().init();

  // Request critical permissions on startup
  try {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.bluetoothAdvertise,
      Permission.location,
      Permission.notification,
    ].request();
  } catch (e) {
    debugPrint('Initial permission request error: $e');
  }

  runApp(const MeshSosAppRoot());
}

class MeshSosAppRoot extends StatelessWidget {
  const MeshSosAppRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<SmartwatchProvider>(create: (_) => SmartwatchProvider()),
        ChangeNotifierProvider<BleService>(create: (_) => BleService()),
        ChangeNotifierProvider<LocationService>(create: (_) => LocationService()..initLocation()),
        ChangeNotifierProvider<AlertService>(create: (_) => AlertService()),
        ChangeNotifierProvider<AiSafetyService>(create: (_) => AiSafetyService()),
        ChangeNotifierProxyProvider2<BleService, LocationService, MeshProvider>(
          create: (ctx) => MeshProvider(
            Provider.of<BleService>(ctx, listen: false),
            Provider.of<LocationService>(ctx, listen: false),
          ),
          update: (ctx, ble, loc, prev) => prev ?? MeshProvider(ble, loc),
        ),
        ChangeNotifierProxyProvider4<BleService, LocationService, AlertService, AiSafetyService, SosProvider>(
          create: (ctx) {
            final ble = Provider.of<BleService>(ctx, listen: false);
            final loc = Provider.of<LocationService>(ctx, listen: false);
            final alert = Provider.of<AlertService>(ctx, listen: false);
            final ai = Provider.of<AiSafetyService>(ctx, listen: false);
            final sos = SosProvider(ble, loc, alert);
            ai.onAutoSosTriggered = (reason, riskScore) {
              sos.setDistressNote(reason);
              sos.triggerSos(silent: false);
            };
            return sos;
          },
          update: (ctx, ble, loc, alert, ai, prev) {
            final sos = prev ?? SosProvider(ble, loc, alert);
            ai.onAutoSosTriggered = (reason, riskScore) {
              sos.setDistressNote(reason);
              sos.triggerSos(silent: false);
            };
            return sos;
          },
        ),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp(
            title: 'Offline Mesh SOS',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.themeData,
            home: const MainNavigationHolder(),
          );
        },
      ),
    );
  }
}

class MainNavigationHolder extends StatefulWidget {
  const MainNavigationHolder({super.key});

  @override
  State<MainNavigationHolder> createState() => _MainNavigationHolderState();
}

class _MainNavigationHolderState extends State<MainNavigationHolder> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    DashboardScreen(),
    ChatScreen(),
    SosScreen(),
    MapRadarScreen(),
    ContactsScreen(),
    ChecklistScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const EmergencyBanner(),
                Expanded(
                  child: IndexedStack(
                    index: _currentIndex,
                    children: _screens,
                  ),
                ),
              ],
            ),
            const AiCountdownOverlay(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        backgroundColor: theme.scaffoldBackgroundColor,
        indicatorColor: theme.colorScheme.primary.withOpacity(0.25),
        onDestinationSelected: (idx) {
          setState(() => _currentIndex = idx);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Nodes',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            selectedIcon: Icon(Icons.warning, color: Colors.red),
            label: 'SOS',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Radar',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.checklist_rtl),
            selectedIcon: Icon(Icons.checklist),
            label: 'Checklist',
          ),
        ],
      ),
    );
  }
}
