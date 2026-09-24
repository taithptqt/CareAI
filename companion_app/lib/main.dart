import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'screens/device_pairing_screen.dart';
import 'screens/sos_button_screen.dart';
import 'services/api_service.dart';
import 'services/local_offline_store.dart';
import 'services/sync_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      // Tác vụ đồng bộ nền định kỳ 15 phút (UC-03 Offline-to-Online Batch Sync)
      final result = await SyncService.instance.syncOfflineSpool();
      debugPrint('[CareAI-Workmanager] Đã đồng bộ nền thành công: ${result.syncedCount} gói tin');
      return true;
    } catch (e) {
      debugPrint('[CareAI-Workmanager] Lỗi đồng bộ nền: $e');
      return false;
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Khởi tạo CSDL SQLite Outbox Spool
  await LocalOfflineStore.instance.database;

  // Khởi tạo Workmanager để đồng bộ nền
  try {
    await Workmanager().initialize(
      callbackDispatcher,
    );

    await Workmanager().registerPeriodicTask(
      'careai_periodic_sync_task',
      'careai_periodic_sync',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
    );
  } catch (e) {
    debugPrint('Không thể khởi tạo Workmanager: $e');
  }

  // Kiểm tra trạng thái ghép đôi
  final isPaired = await ApiService.instance.isPaired();

  runApp(CareAiCompanionApp(initialScreen: isPaired ? const SosButtonScreen() : const DevicePairingScreen()));
}

class CareAiCompanionApp extends StatelessWidget {
  final Widget initialScreen;

  const CareAiCompanionApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CareAI Companion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: initialScreen,
    );
  }
}
