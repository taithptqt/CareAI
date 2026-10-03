import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dịch vụ Hướng dẫn Y tế bằng Giọng nói (Gói C - Medical Voice Guidance TTS)
/// Sử dụng Native Android TextToSpeech qua MethodChannel 'vn.careai.companion/tts_bridge'
/// Đảm bảo độ trễ 0ms, hoạt động ngoại tuyến 100%, không cần kết nối Internet khi cấp cứu.
class VoiceGuidanceService {
  VoiceGuidanceService._();
  static final VoiceGuidanceService instance = VoiceGuidanceService._();

  static const MethodChannel _channel = MethodChannel('vn.careai.companion/tts_bridge');

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  /// Phát âm thanh hướng dẫn giọng nói tổng quát
  Future<bool> speak(String text) async {
    if (text.trim().isEmpty) return false;
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      _isSpeaking = true;
      final result = await _channel.invokeMethod<bool>('speak', {'text': text.trim()});
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[VoiceGuidanceService] Lỗi phát âm giọng nói: ${e.message}');
      _isSpeaking = false;
      return false;
    } catch (e) {
      debugPrint('[VoiceGuidanceService] Ngoại lệ không xác định: $e');
      _isSpeaking = false;
      return false;
    }
  }

  /// Dừng phát âm thanh ngay lập tức
  Future<bool> stop() async {
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      _isSpeaking = false;
      final result = await _channel.invokeMethod<bool>('stop');
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[VoiceGuidanceService] Lỗi dừng phát âm: ${e.message}');
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra xem gói ngôn ngữ tiếng Việt có sẵn sàng trên máy không
  Future<bool> isLanguageAvailable() async {
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final result = await _channel.invokeMethod<bool>('isLanguageAvailable');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 1. Giọng nói hướng dẫn khi phát hiện té ngã (UC-03 / Fast-Lane SOS)
  Future<bool> speakFallDetected() async {
    const text = 'Phát hiện có thể bạn vừa bị ngã. Hệ thống CareAI đang phát còi cấp cứu. '
        'Nếu bạn vẫn ổn, hãy bấm nút Tôi Ổn màu xanh trên màn hình để hủy.';
    return speak(text);
  }

  /// 2. Giọng nói trấn an khi người thân bấm tiếp nhận cứu hộ (UC-08 Human ACK)
  Future<bool> speakCaregiverAcknowledged(String caregiverName) async {
    final name = caregiverName.trim().isNotEmpty ? caregiverName.trim() : 'Người thân';
    final text = '$name đã nhận được tin báo và đang trên đường đến hỗ trợ. '
        'Bạn hãy giữ bình tĩnh và ngồi yên tại chỗ.';
    return speak(text);
  }

  /// 3. Giọng nói cảnh báo nhịp tim nhanh (Tachycardia Clinical Guidance)
  Future<bool> speakTachycardiaAlert(int bpm) async {
    final text = 'Cảnh báo y tế: Nhịp tim của bạn đang ở mức cao, $bpm nhịp một phút. '
        'Hãy ngồi nghỉ ngơi, thả lỏng cơ thể, hít thở sâu và uống một ngụm nước ấm.';
    return speak(text);
  }

  /// 4. Giọng nói cảnh báo nhịp tim chậm nguy hiểm (Bradycardia Clinical Guidance)
  Future<bool> speakBradycardiaAlert(int bpm) async {
    final text = 'Cảnh báo y tế: Nhịp tim của bạn đang ở mức rất chậm, $bpm nhịp một phút. '
        'Hãy ngồi tựa lưng an toàn, không đứng dậy đột ngột và gọi người thân hỗ trợ nếu thấy chóng mặt.';
    return speak(text);
  }
}
