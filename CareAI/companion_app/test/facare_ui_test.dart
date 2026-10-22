import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:careai_companion/caregiver/screens/login_screen.dart';
import 'package:careai_companion/caregiver/screens/home_screen.dart';
import 'package:careai_companion/caregiver/screens/elder_dashboard_screen.dart';
import 'package:careai_companion/caregiver/screens/health_corner_screen.dart';
import 'package:careai_companion/caregiver/services/health_report_api.dart';
import 'package:careai_companion/caregiver/screens/family_management_screen.dart';
import 'package:careai_companion/caregiver/screens/incident_history_screen.dart';
import 'package:careai_companion/caregiver/models/models.dart';
import 'package:careai_companion/caregiver/screens/incident_detail_screen.dart';
import 'package:careai_companion/caregiver/widgets/family_overview.dart';
import 'package:careai_companion/caregiver/widgets/heart_rate_chart_widget.dart';
import 'package:careai_companion/screens/device_pairing_screen.dart';
import 'package:careai_companion/screens/role_selection_screen.dart';
import 'package:careai_companion/screens/fall_countdown_dialog.dart';
import 'package:careai_companion/models/fall_event.dart';
import 'package:careai_companion/screens/sos_button_screen.dart';
import 'package:careai_companion/theme/careai_theme.dart';
import 'package:careai_companion/widgets/careai_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

const _reviewName = 'Nguyễn Thị Minh Anh';

class _ReviewHealthApi implements HealthReportApi {
  @override
  Future<Map<String, dynamic>> get(
    String elderId,
    String resource, {
    int? beforeId,
  }) async {
    if (resource.startsWith('weekly-reports/')) {
      return {
        'weekStartUtc': '2026-10-11T00:00:00Z',
        'content': '1. Tổng quan sức khỏe tuần\nDữ liệu mẫu dùng để kiểm tra giao diện báo cáo. Nhịp tim 72 bpm; trung bình 1200 bước; SpO2 98%; 0 nhận định bất thường.\n2. Điểm tích cực & cần lưu ý\nThông tin trong bài kiểm tra, không phải hồ sơ người dùng.\n3. Lời khuyên sinh hoạt\nNội dung mẫu để kiểm tra trình bày.',
      };
    }
    return {
      'items': resource == 'insights'
          ? [
              {
                'id': 1,
                'insightType': 'NIGHT_HEART_RATE_SPIKE',
                'windowEndUtc': '2026-10-18T06:00:00Z',
                'observedValue': 100,
                'baselineValue': 65,
              },
            ]
          : [
              {
                'id': 1,
                'weekStartUtc': '2026-10-11T00:00:00Z',
                'weekEndUtc': '2026-10-18T00:00:00Z',
                'source': 'RULE_BASED',
              },
            ],
      'nextBeforeId': null,
    };
  }
}

http.Client _dashboardReviewClient({bool withData = false}) =>
    MockClient((request) async {
      final now = DateTime.now().toUtc();
      final timestamps = [
        now.subtract(const Duration(hours: 2)).toIso8601String(),
        now.toIso8601String(),
      ];
      Map<String, dynamic> vital(String metric, double value, String unit) => {
        'metricType': metric,
        'value': value,
        'unit': unit,
        'timestamp': now.toIso8601String(),
        'statusColor': 'GREEN',
      };
      final Object body;
      final path = request.url.path;
      if (path.endsWith('/dashboard/elder/ui-review-elder')) {
        body = {
          'elderProfileId': 'ui-review-elder',
          'fullName': _reviewName,
          'age': 76,
          'deviceStatus': withData ? 'ONLINE' : 'OFFLINE',
          'statusBadgeColor': withData ? 'GREEN' : 'GRAY',
          'todaySteps': withData ? 1200 : 0,
          'stepGoal': 6000,
          'watchStatus': withData ? 'ONLINE' : 'NOT_PAIRED',
          if (withData) ...{
            'watchModel': 'Đồng hồ kiểm tra UI',
            'isWatchWorn': true,
            'isWatchCharging': false,
            'watchBatteryLevel': 75,
            'latestHeartRate': vital('HEART_RATE', 72, 'bpm'),
            'latestSpO2': vital('SPO2', 98, '%'),
            'latestBloodPressure': vital('BLOOD_PRESSURE', 120, 'mmHg'),
            'lastSyncedAt': now.toIso8601String(),
          },
        };
      } else if (path.endsWith('/thresholds')) {
        body = {'elderProfileId': 'ui-review-elder'};
      } else if (path.contains('/vitals/')) {
        body = !withData
            ? <String, dynamic>{}
            : switch (path.split('/').last) {
                'heart-rate-24h' => {
                  'points': [
                    for (final t in timestamps) {'timestamp': t, 'value': 72},
                  ],
                  'minHeartRate': 72,
                  'maxHeartRate': 72,
                  'avgHeartRate': 72,
                  'latestHeartRate': 72,
                },
                'blood-pressure-history' => {
                  'points': [
                    for (final t in timestamps)
                      {'timestamp': t, 'systolic': 120, 'diastolic': 80},
                  ],
                  'latestSystolic': 120,
                  'latestDiastolic': 80,
                },
                'spo2-24h' => {
                  'points': [
                    for (final t in timestamps) {'timestamp': t, 'value': 98},
                  ],
                  'minSpo2': 98,
                  'maxSpo2': 98,
                  'avgSpo2': 98,
                  'latestSpo2': 98,
                },
                'hourly-steps-24h' => {
                  'hourlySteps': [
                    for (var hour = 0; hour < 24; hour++)
                      {'hour': hour, 'steps': 50},
                  ],
                  'totalStepsToday': 1200,
                  'peakHour': 9,
                  'peakSteps': 50,
                },
                'sleep-summary' => {
                  'elderProfileId': 'ui-review-elder',
                  'date': now.toIso8601String(),
                  'totalSleepMinutes': 420,
                  'deepSleepMinutes': 100,
                  'lightSleepMinutes': 280,
                  'remSleepMinutes': 40,
                  'awakeMinutes': 10,
                  'wakeCount': 1,
                  'sleepQuality': 'Tốt',
                  'statusColor': 'GREEN',
                  'sleepStartTime': now
                      .subtract(const Duration(hours: 9))
                      .toIso8601String(),
                  'sleepEndTime': now
                      .subtract(const Duration(hours: 2))
                      .toIso8601String(),
                },
                _ => throw StateError('Unexpected dashboard resource: $path'),
              };
      } else {
        throw StateError('Unexpected dashboard fixture request: $path');
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

http.Client _familyReviewClient() => MockClient((request) async {
  Object body;
  var status = 200;
  if (request.url.path.endsWith('/incidents/active')) {
    body = [];
  } else if (request.url.path.endsWith('/members')) {
    body = [
      {
        'caregiverId': 'primary',
        'fullName': _reviewName,
        'role': 'Primary',
        'email': 'minhanh.family.review@example.com',
        'phoneNumber': '0900000000',
        'assignedAt': '2026-10-21T08:00:00Z',
      },
      {
        'caregiverId': 'secondary',
        'fullName': 'Nguyễn Hoàng Quang Minh',
        'role': 'Secondary',
        'email': 'quangminh.family.review@example.com',
        'phoneNumber': '0900000001',
        'assignedAt': '2026-10-21T08:00:00Z',
      },
    ];
  } else if (request.url.path.endsWith('/invitations')) {
    status = 201;
    body = {'invitationCode': 'ABC123', 'expiresAt': '2026-10-22T08:00:00Z'};
  } else if (request.url.path.endsWith('/caregivers/elders')) {
    body = [
      {'id': 'ui-review-elder', 'fullName': _reviewName},
    ];
  } else if (request.url.path.endsWith('/incidents')) {
    body = {
      'page': 1,
      'totalCount': 1,
      'totalPages': 1,
      'items': [
        {
          'id': 'ui-review-history',
          'elderProfileId': 'ui-review-elder',
          'elderName': _reviewName,
          'triggeredByDeviceId': 'ui-review-device',
          'emergencyType': 'MANUAL_SOS',
          'severity': 'Critical',
          'status': 'Resolved',
          'triggeredAt': '2026-10-21T08:00:00Z',
          'resolvedAt': '2026-10-21T08:05:00Z',
          'resolutionNotes': 'Gia đình đã hỗ trợ người thân.',
          'snapshot': {'heartRateBpm': 92, 'spO2Percent': 97},
          'timeline': [],
        },
      ],
    };
  } else {
    throw StateError(
      'Unexpected UI fixture request: ${request.method} ${request.url.path}',
    );
  }
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  setUpAll(() async {
    final loader = FontLoader('BeVietnamPro');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      loader.addFont(
        rootBundle.load('assets/fonts/be_vietnam_pro/BeVietnamPro-$weight.ttf'),
      );
    }
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  Future<void> mount(
    WidgetTester tester,
    Widget screen, {
    required double width,
    double textScale = 1,
    GlobalKey? captureKey,
    bool settle = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: CareAiTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: RepaintBoundary(key: captureKey, child: child!),
        ),
        home: screen,
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
    final directory = Platform.environment['CAREAI_UI_CAPTURE_DIR'];
    if (directory == null) return;
    final previousShadowSetting = debugDisableShadows;
    debugDisableShadows = false;
    for (final object in tester.allRenderObjects) {
      object.markNeedsPaint();
    }
    await tester.pump();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    try {
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File('$directory/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    } finally {
      debugDisableShadows = previousShadowSetting;
      for (final object in tester.allRenderObjects) {
        object.markNeedsPaint();
      }
      await tester.pump();
    }
  }

  for (final width in [320.0, 390.0, 600.0]) {
    for (final textScale in [1.0, 2.0]) {
      testWidgets('health reports: width $width, text scale $textScale', (
        tester,
      ) async {
        final key = GlobalKey();
        await mount(
          tester,
          HealthCornerScreen(
            elderId: 'ui-review-elder',
            api: _ReviewHealthApi(),
          ),
          width: width,
          textScale: textScale,
          captureKey: key,
        );
        expect(find.text('Nhịp tim ban đêm tăng'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          key,
          'health-insights-${width.toInt()}-$textScale',
        );
        await tester.ensureVisible(find.text('Báo cáo tuần'));
        await tester.tap(find.text('Báo cáo tuần'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await capture(
          tester,
          key,
          'health-reports-${width.toInt()}-$textScale',
        );
        final report = find.textContaining('Tuần từ 11/10/2026');
        await tester.ensureVisible(report);
        await tester.tap(report);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final metric in ['72 bpm', '1200 bước', '98%', '0 lần']) {
          expect(find.text(metric), findsOneWidget);
        }
        expect(find.text('Ổn định'), findsNothing);
        expect(
          find.textContaining(
            'Dữ liệu mẫu dùng để kiểm tra giao diện báo cáo.',
          ),
          findsOneWidget,
        );
        await capture(
          tester,
          key,
          'health-report-detail-${width.toInt()}-$textScale',
        );
        await tester.ensureVisible(
          find.text('Báo cáo hỗ trợ theo dõi, không phải chẩn đoán y khoa.'),
        );
        expect(tester.takeException(), isNull);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Góc Sức Khỏe AI'), findsOneWidget);
      });
      testWidgets('sos screen: width $width, text scale $textScale', (
        tester,
      ) async {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/geolocator'),
          (call) async {
            if (call.method == 'checkPermission' ||
                call.method == 'requestPermission') {
              return 0;
            }
            if (call.method == 'isLocationServiceEnabled') return false;
            throw PlatformException(
              code: 'PERMISSION_DENIED',
              message: 'UI fixture has no GPS',
            );
          },
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('vn.careai.companion/gps_bridge'),
          (_) async => null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/sensors/method'),
          (_) async => null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel(
            'dev.fluttercommunity.plus/sensors/accelerometer',
          ),
          (_) async => null,
        );
        final previousFactory = sqflite.databaseFactoryOrNull;
        sqflite.databaseFactory = sqflite.databaseFactorySqflitePlugin;
        addTearDown(() => sqflite.databaseFactory = previousFactory);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('com.tekartik.sqflite'),
          (call) async {
            switch (call.method) {
              case 'getDatabasesPath':
                return '${Directory.systemTemp.path}/careai-ui-review-mock';
              case 'openDatabase':
                return {'id': 1};
              case 'query':
                final sql = (call.arguments as Map)['sql'] as String? ?? '';
                if (sql.contains('user_version')) {
                  return [
                    {'user_version': 2},
                  ];
                }
                if (sql.contains('journal_mode')) {
                  return [
                    {'journal_mode': 'wal'},
                  ];
                }
                if (sql.contains('COUNT(*)')) {
                  return [
                    {'count': 0},
                  ];
                }
                return <Map<String, Object?>>[];
              default:
                return null;
            }
          },
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('vn.careai.companion/fall_bridge'),
          (call) async => call.method == 'getConnectedWatchStatus'
              ? {'isConnected': false}
              : true,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          (call) async => call.method == 'requestPermissions'
              ? {for (final permission in call.arguments as List) permission: 0}
              : 0,
        );
        SharedPreferences.setMockInitialValues({
          'elder_name': _reviewName,
          'last_paired_watch_name': 'Đồng hồ kiểm tra giao diện',
        });
        await http.runWithClient(
          () async {
            final key = GlobalKey();
            await mount(
              tester,
              const SosButtonScreen(),
              width: width,
              textScale: textScale,
              captureKey: key,
              settle: false,
            );
            await tester.pump(const Duration(seconds: 2));
            expect(tester.takeException(), isNull);
            await capture(
              tester,
              key,
              'sos-screen-${width.toInt()}-$textScale',
            );
            expect(find.text('SOS').hitTestable(), findsOneWidget);
            final sosButton = find
                .ancestor(of: find.text('SOS'), matching: find.byType(InkWell))
                .first;
            final buttonBounds = tester.getRect(sosButton);
            final bodyBounds = tester.getRect(find.byType(ListView).first);
            expect(buttonBounds.top, greaterThanOrEqualTo(bodyBounds.top));
            expect(buttonBounds.bottom, lessThanOrEqualTo(bodyBounds.bottom));
            expect(
              find.byTooltip('Cài đặt thiết bị').hitTestable(),
              findsOneWidget,
            );
            await tester.tap(find.byTooltip('Cài đặt thiết bị'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            await capture(
              tester,
              key,
              'sos-settings-${width.toInt()}-$textScale',
            );
            expect(tester.takeException(), isNull);
            final closeSettings = find.byTooltip('Đóng cài đặt');
            expect(
              tester
                  .getSize(
                    find
                        .ancestor(
                          of: closeSettings,
                          matching: find.byType(IconButton),
                        )
                        .first,
                  )
                  .shortestSide,
              greaterThanOrEqualTo(48),
            );
            await tester.tap(closeSettings);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            await tester.tap(find.byTooltip('Cài đặt thiết bị'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            final rename = find.text('Đổi tên đồng hồ');
            await tester.ensureVisible(rename);
            await tester.tap(rename);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            tester.view.viewInsets = const FakeViewPadding(bottom: 300);
            addTearDown(tester.view.resetViewInsets);
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            final nameField = find.descendant(
              of: find.byType(AlertDialog),
              matching: find.byType(TextFormField),
            );
            await tester.ensureVisible(nameField);
            expect(nameField.hitTestable(), findsOneWidget);
            expect(find.text('Lưu tên').hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
            await capture(
              tester,
              key,
              'sos-rename-keyboard-${width.toInt()}-$textScale',
            );
            await tester.tap(find.text('Hủy'));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            tester.view.resetViewInsets();
            await tester.pumpWidget(const SizedBox());
            await tester.pump();
          },
          () =>
              MockClient((_) async => http.Response('UI review offline', 503)),
        );
      });
      testWidgets('fall dialog: width $width, text scale $textScale', (
        tester,
      ) async {
        String? cancelledEvent;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('vn.careai.companion/fall_bridge'),
          (call) async {
            if (call.method == 'cancelFallAlarm') {
              cancelledEvent = (call.arguments as Map)['eventId'] as String;
            }
            return true;
          },
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('vn.careai.companion/tts_bridge'),
          (_) async => true,
        );
        final key = GlobalKey();
        await mount(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => FallCountdownDialog(
                      event: FallEvent(
                        eventId: 'ui-review-fall',
                        timestamp: DateTime.now().millisecondsSinceEpoch,
                        secondsRemaining: 30,
                        isFromHardwareWatch: true,
                      ),
                    ),
                  ),
                  child: const Text('Open review dialog'),
                ),
              ),
            ),
          ),
          width: width,
          textScale: textScale,
          captureKey: key,
        );
        await tester.tap(find.text('Open review dialog'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await capture(tester, key, 'fall-dialog-${width.toInt()}-$textScale');
        expect(tester.takeException(), isNull);
        final cancel = find.text('Tôi vẫn ổn');
        final sos = find.text('Gửi SOS ngay');
        expect(find.text('30').hitTestable(), findsOneWidget);
        expect(cancel.hitTestable(), findsOneWidget);
        expect(sos.hitTestable(), findsOneWidget);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(cancelledEvent, 'ui-review-fall');
        expect(find.byType(FallCountdownDialog), findsNothing);
      });
      for (final withData in [false, true]) {
        testWidgets(
          'dashboard $withData: width $width, text scale $textScale',
          (tester) async {
            await http.runWithClient(() async {
              final key = GlobalKey();
              await mount(
                tester,
                const ElderDashboardScreen(
                  elderProfileId: 'ui-review-elder',
                  elderName: _reviewName,
                ),
                width: width,
                textScale: textScale,
                captureKey: key,
              );
              await capture(
                tester,
                key,
                'dashboard-$withData-${width.toInt()}-$textScale',
              );
              expect(tester.takeException(), isNull);
              if (withData) {
                for (final label in [
                  'Nhịp tim',
                  'Huyết áp',
                  'SpO2',
                  'Vận động',
                ]) {
                  final tab = find.text(label).last;
                  await tester.ensureVisible(tab);
                  await tester.tap(tab);
                  await tester.pumpAndSettle();
                  expect(tester.takeException(), isNull);
                  await capture(
                    tester,
                    key,
                    'dashboard-chart-$label-${width.toInt()}-$textScale',
                  );
                  final chart = label != 'Vận động'
                      ? find.byType(LineChart)
                      : find.byType(BarChart);
                  await tester.ensureVisible(chart);
                  await tester.pumpAndSettle();
                  await capture(
                    tester,
                    key,
                    'dashboard-plot-$label-${width.toInt()}-$textScale',
                  );
                  if (textScale > 1.4) {
                    final horizontal = find.byWidgetPredicate(
                      (widget) =>
                          widget is Scrollable &&
                          widget.axisDirection == AxisDirection.right,
                    );
                    final position = tester
                        .state<ScrollableState>(horizontal)
                        .position;
                    if (position.maxScrollExtent > 0) {
                      await tester.drag(horizontal, const Offset(-180, 0));
                      await tester.pumpAndSettle();
                      expect(position.pixels, greaterThan(0));
                    }
                  }
                  expect(tester.takeException(), isNull);
                }
              }
              await tester.scrollUntilVisible(
                find.text('Mã PIN Ghép Nối Thiết Bị'),
                400,
                scrollable: find.byType(Scrollable).first,
              );
              expect(tester.takeException(), isNull);
              if (!withData) {
                expect(find.text('Chưa có dữ liệu'), findsWidgets);
                expect(find.text('Bình thường'), findsNothing);
              }
              await tester.pumpWidget(const SizedBox());
            }, () => _dashboardReviewClient(withData: withData));
          },
        );
      }
      testWidgets('home: width $width, text scale $textScale', (tester) async {
        await http.runWithClient(() async {
          SharedPreferences.setMockInitialValues({
            'caregiver_name': 'Minh Anh',
            'caregiver_email': 'minhanh.ui.review@example.com',
            'caregiver_power_onboarding_dismissed': true,
          });
          final key = GlobalKey();
          await mount(
            tester,
            const HomeScreen(),
            width: width,
            textScale: textScale,
            captureKey: key,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Minh Anh'), findsOneWidget);
          await capture(tester, key, 'home-${width.toInt()}-$textScale');
          await tester.scrollUntilVisible(
            find.text('Ghép thiết bị'),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            key,
            'home-family-card-${width.toInt()}-$textScale',
          );
          await tester.tap(find.byTooltip('Sự cố'));
          await tester.pumpAndSettle();
          expect(find.text('Chưa có sự cố đang mở'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Tài khoản'));
          await tester.pumpAndSettle();
          expect(find.text('Tài khoản của bạn'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            key,
            'home-account-${width.toInt()}-$textScale',
          );
          await tester.tap(find.byTooltip('Thêm người cao tuổi'));
          await tester.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          expect(find.text('Thêm người thân'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            key,
            'home-add-profile-${width.toInt()}-$textScale',
          );
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          final dialog = find.byType(AlertDialog);
          final fields = find.descendant(
            of: dialog,
            matching: find.byType(TextField),
          );
          await tester.ensureVisible(fields.last);
          await tester.pumpAndSettle();
          expect(fields.last.hitTestable(), findsOneWidget);
          expect(find.text('Hủy').hitTestable(), findsOneWidget);
          expect(find.text('Tạo hồ sơ').hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await capture(
            tester,
            key,
            'home-add-profile-keyboard-${width.toInt()}-$textScale',
          );
          tester.view.resetViewInsets();
          await tester.pumpAndSettle();
          await tester.tap(find.text('Hủy'));
          await tester.pumpAndSettle();
          await tester.pumpWidget(const SizedBox());
        }, _familyReviewClient);
      });
      for (final role in ['primary', 'secondary']) {
        testWidgets('family $role: width $width, text scale $textScale', (
          tester,
        ) async {
          await http.runWithClient(() async {
            SharedPreferences.setMockInitialValues({'caregiver_id': role});
            final key = GlobalKey();
            await mount(
              tester,
              const FamilyManagementScreen(
                elderId: 'ui-review-elder',
                elderName: _reviewName,
              ),
              width: width,
              textScale: textScale,
              captureKey: key,
            );
            expect(tester.takeException(), isNull);
            expect(find.text('Bên nhau chăm sóc'), findsOneWidget);
            final invite = find.text('Mời người thân cùng chăm sóc');
            expect(invite, role == 'primary' ? findsOneWidget : findsNothing);
            await capture(
              tester,
              key,
              'family-$role-${width.toInt()}-$textScale',
            );
            await tester.scrollUntilVisible(
              find.text(
                'Nguyễn Hoàng Quang Minh${role == 'secondary' ? ' (Bạn)' : ''}',
              ),
              250,
              scrollable: find.byType(Scrollable).first,
            );
            expect(tester.takeException(), isNull);
            expect(
              find.byTooltip('Thu hồi quyền thành viên'),
              role == 'primary' ? findsOneWidget : findsNothing,
            );
            if (role == 'primary') {
              await tester.tap(invite);
              await tester.pumpAndSettle();
              expect(find.text('ABC123'), findsOneWidget);
              final editable = tester
                  .state<EditableTextState>(
                    find.descendant(
                      of: find.byType(SelectableText),
                      matching: find.byType(EditableText),
                    ),
                  )
                  .renderEditable;
              expect(
                editable.getBoxesForSelection(
                  const TextSelection(baseOffset: 0, extentOffset: 6),
                ),
                hasLength(1),
              );
              expect(tester.takeException(), isNull);
              await capture(
                tester,
                key,
                'family-invite-${width.toInt()}-$textScale',
              );
              String? copiedCode;
              tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
                SystemChannels.platform,
                (call) async {
                  if (call.method == 'Clipboard.setData') {
                    copiedCode = (call.arguments as Map)['text'] as String;
                  }
                  return null;
                },
              );
              await tester.ensureVisible(find.text('Sao chép mã'));
              await tester.tap(find.text('Sao chép mã'));
              await tester.pump();
              expect(copiedCode, 'ABC123');
              await tester.ensureVisible(find.text('Xong'));
              await tester.tap(find.text('Xong'));
              await tester.pumpAndSettle();
              expect(find.text('ABC123'), findsNothing);
            }
          }, _familyReviewClient);
        });
      }
      testWidgets('history: width $width, text scale $textScale', (
        tester,
      ) async {
        await http.runWithClient(() async {
          final key = GlobalKey();
          await mount(
            tester,
            const IncidentHistoryScreen(
              initialElderProfileId: 'ui-review-elder',
              initialElderName: _reviewName,
            ),
            width: width,
            textScale: textScale,
            captureKey: key,
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Lịch sử chăm sóc'), findsOneWidget);
          expect(
            tester.getSize(find.byType(DropdownButton<String>)).width,
            greaterThan(width - 90),
          );
          expect(find.text(_reviewName), findsWidgets);
          await capture(tester, key, 'history-${width.toInt()}-$textScale');
        }, _familyReviewClient);
      });
      for (final status in ['Open', 'Acknowledged', 'Resolved']) {
        testWidgets('incident $status: width $width, text scale $textScale', (
          tester,
        ) async {
          final key = GlobalKey();
          final incident = Incident.fromJson({
            'id': 'ui-review-incident',
            'elderProfileId': 'ui-review-elder',
            'elderName': 'Nguyễn Thị Minh Anh',
            'triggeredByDeviceId': 'ui-review-device',
            'emergencyType': 'MANUAL_SOS',
            'severity': 'Critical',
            'status': status,
            'triggeredAt': '2026-10-21T08:00:00Z',
            if (status != 'Open') 'acknowledgedAt': '2026-10-21T08:01:00Z',
            if (status == 'Resolved') 'resolvedAt': '2026-10-21T08:02:00Z',
            if (status == 'Resolved')
              'resolutionNotes': 'Gia đình đã liên hệ và hỗ trợ người thân.',
            'snapshot': {'heartRateBpm': 92, 'spO2Percent': 97},
            'timeline': [],
          });
          await mount(
            tester,
            IncidentDetailScreen(incident: incident),
            width: width,
            textScale: textScale,
            captureKey: key,
          );
          final layoutError = tester.takeException();
          expect(
            layoutError,
            isNull,
            reason: layoutError is FlutterError
                ? layoutError.diagnostics
                      .map((node) => node.toStringDeep())
                      .join('\n')
                : null,
          );
          if (status != 'Resolved') {
            expect(find.text('Gọi 115').hitTestable(), findsOneWidget);
            expect(
              find
                  .text(
                    status == 'Open' ? 'Tiếp nhận sự cố' : 'Giải quyết sự cố',
                  )
                  .hitTestable(),
              findsOneWidget,
            );
          }
          await capture(
            tester,
            key,
            'incident-$status-${width.toInt()}-$textScale',
          );
          await tester.scrollUntilVisible(
            find.text('Dòng thời gian sự kiện'),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
      for (final screen in <String, Widget>{
        'role': const RoleSelectionScreen(),
        'login': const LoginScreen(),
        'pairing': const DevicePairingScreen(),
        'heart-rate': Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: HeartRateChartWidget(
              incidentTriggeredAt: DateTime.utc(2026, 10, 21, 8),
              window: IncidentHeartRateWindow(
                incidentTriggeredAt: DateTime.utc(2026, 10, 21, 8),
                windowStart: DateTime.utc(2026, 10, 21, 7, 45),
                windowEnd: DateTime.utc(2026, 10, 21, 8, 15),
                samples: [
                  HeartRateSample(
                    bpm: 75,
                    timestamp: DateTime.utc(2026, 10, 21, 7, 50),
                  ),
                  HeartRateSample(
                    bpm: 185,
                    timestamp: DateTime.utc(2026, 10, 21, 8),
                  ),
                  HeartRateSample(
                    bpm: 90,
                    timestamp: DateTime.utc(2026, 10, 21, 8, 5),
                  ),
                ],
              ),
            ),
          ),
        ),
        'overview': Scaffold(
          appBar: AppBar(title: const CareAiBrand()),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              CareAiFamilyOverview(
                caregiverName: 'Minh Anh',
                elderCount: 3,
                openIncidents: 2,
                isLoadingIncidents: false,
                onIncidents: () {},
              ),
            ],
          ),
          bottomNavigationBar: CareAiFamilyDock(
            index: 0,
            openIncidents: 0,
            onSelect: (_) {},
            onAdd: () {},
            onHistory: () {},
          ),
        ),
      }.entries) {
        testWidgets('${screen.key}: width $width, text scale $textScale', (
          tester,
        ) async {
          final key = GlobalKey();
          await mount(
            tester,
            screen.value,
            width: width,
            textScale: textScale,
            captureKey: key,
          );
          expect(tester.takeException(), isNull);
          expect(
            Theme.of(tester.element(find.byType(Scaffold)))
                .textTheme
                .bodyMedium!
                .fontFamily,
            'BeVietnamPro',
          );
          await capture(
            tester,
            key,
            '${screen.key}-${width.toInt()}-$textScale',
          );
        });
      }
    }

    testWidgets('navbar: targets and callbacks at width $width', (
      tester,
    ) async {
      int? selected;
      var added = false;
      var historyOpened = false;
      final key = GlobalKey();
      await mount(
        tester,
        Scaffold(
          bottomNavigationBar: CareAiFamilyDock(
            index: 0,
            openIncidents: 3,
            onSelect: (value) => selected = value,
            onAdd: () => added = true,
            onHistory: () => historyOpened = true,
          ),
        ),
        width: width,
        captureKey: key,
      );
      expect(tester.takeException(), isNull);
      for (final label in [
        'Gia đình',
        'Sự cố',
        'Lịch sử sự cố',
        'Tài khoản',
        'Thêm người cao tuổi',
      ]) {
        final target = find.byTooltip(label);
        expect(target.hitTestable(), findsOneWidget);
        final size = tester.getSize(target);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      await tester.tap(find.byTooltip('Sự cố'));
      expect(selected, 1);
      await tester.tap(find.byTooltip('Tài khoản'));
      expect(selected, 2);
      await tester.tap(find.byTooltip('Lịch sử sự cố'));
      expect(historyOpened, isTrue);
      await tester.tap(find.byTooltip('Thêm người cao tuổi'));
      expect(added, isTrue);
      await tester.pumpAndSettle();
      await capture(tester, key, 'navbar-${width.toInt()}');
    });
  }
}
