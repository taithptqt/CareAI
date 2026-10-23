import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'caregiver/screens/home_screen.dart';
import 'caregiver/screens/login_screen.dart';
import 'caregiver/services/caregiver_api_service.dart';
import 'caregiver/services/caregiver_push_service.dart';
import 'screens/device_pairing_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/sos_button_screen.dart';
import 'services/api_service.dart';
import 'services/local_offline_store.dart';
import 'services/sync_service.dart';
import 'theme/careai_theme.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      // Tác vụ gặt hái sinh hiệu Health Connect & đồng bộ nền định kỳ 15 phút (Nhiệm vụ 1.1)
      final result = await SyncService.instance.harvestAndSyncCycle();
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

  // SQLite và Workmanager chỉ được hỗ trợ trên native platforms.
  if (!kIsWeb) {
    await LocalOfflineStore.instance.database;
  }

  // 2. Khởi tạo Dịch vụ Người Thân (SharedPreferences & Server URL)
  await CaregiverApiService.instance.init();

  // 3. Khởi tạo Workmanager để đồng bộ nền thiết bị
  if (!kIsWeb) {
    try {
      if (Platform.isAndroid) {
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
      } else if (Platform.isIOS) {
        // Trên iOS: Workmanager sử dụng BGTaskScheduler đã được khai báo trong AppDelegate & Info.plist
        await Workmanager().initialize(
          callbackDispatcher,
        );

        try {
          await Workmanager().registerPeriodicTask(
            'careai_periodic_sync_task',
            'careai_periodic_sync',
            frequency: const Duration(minutes: 15),
          );
        } catch (iosBgError) {
          debugPrint('[CareAI-Workmanager] Lưu ý đăng ký nền trên iOS: $iosBgError');
        }
      }
    } catch (e) {
      debugPrint('Không thể khởi tạo Workmanager: $e');
    }
  }

  // 4. Kiểm tra vai trò đã chọn trước đó
  final prefs = await SharedPreferences.getInstance();
  final savedRole = prefs.getString(RoleSelectionScreen.prefSelectedRole);

  Widget initialScreen;

  if (savedRole == 'elder') {
    // Chế độ Người cao tuổi: Kiểm tra trạng thái ghép đôi
    final isPaired = await ApiService.instance.isPaired();
    initialScreen = isPaired ? const SosButtonScreen() : const DevicePairingScreen();
  } else if (savedRole == 'caregiver') {
    // Chế độ Người thân: Kiểm tra đăng nhập JWT và tính sở hữu với Người cao tuổi trên máy
    final currentElderId = await ApiService.instance.getElderProfileId();
    final canEnter = await CaregiverApiService.instance.verifyOrLogoutIfMismatchedElder(currentElderId);
    initialScreen = canEnter ? const HomeScreen() : const LoginScreen();
  } else {
    // Chưa chọn vai trò -> Hiển thị Màn hình Chọn Vai Trò
    initialScreen = const RoleSelectionScreen();
  }

  runApp(CareAiUnifiedApp(initialScreen: initialScreen));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    CaregiverPushService.instance.initialize();
  });
}

class CareAiUnifiedApp extends StatelessWidget {
  final Widget initialScreen;

  const CareAiUnifiedApp({super.key, required this.initialScreen});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: CaregiverPushService.instance.navigatorKey,
      title: 'CareAI',
      debugShowCheckedModeBanner: false,
      theme: CareAiTheme.light,
      home: initialScreen,
    );
  }
}
