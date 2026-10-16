import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Hỗ trợ bản đồ 2 lớp:
/// - Lớp 1 (Ưu tiên): Bản đồ nội địa Việt Nam (VIETMAP) khi có API Key
/// - Lớp 2 (Dự phòng): Bản đồ quốc tế chuẩn OpenStreetMap (OSM France CDN) khi không có API Key,
///   kèm lớp phủ (Sovereignty Marker Layer) khẳng định chủ quyền 2 quần đảo Hoàng Sa và Trường Sa của Việt Nam.
class MapSovereigntyHelper {
  /// Biến môi trường API Key Vietmap
  static const String vietmapKey = String.fromEnvironment('CAREAI_VIETMAP_API_KEY');

  /// Kiểm tra có cấu hình API Key Vietmap hợp lệ hay không
  static bool get hasVietmapKey => vietmapKey.trim().isNotEmpty;

  /// Tạo TileLayer 2 lớp linh hoạt
  static TileLayer buildTileLayer() {
    if (hasVietmapKey) {
      return TileLayer(
        urlTemplate: 'https://maps.vietmap.vn/maps/tiles/st/{z}/{x}/{y}.png?apikey=$vietmapKey',
        userAgentPackageName: 'vn.careai.companion',
        maxZoom: 19,
      );
    }
    return TileLayer(
      urlTemplate: 'https://{s}.tile.openstreetmap.fr/osmfr/{z}/{x}/{y}.png',
      subdomains: const ['a', 'b', 'c'],
      userAgentPackageName: 'vn.careai.companion',
      maxZoom: 19,
    );
  }

  /// Danh sách Marker khẳng định chủ quyền 2 quần đảo Hoàng Sa và Trường Sa của Việt Nam
  static List<Marker> buildSovereigntyMarkers() {
    return [
      // Quần đảo Hoàng Sa (TP. Đà Nẵng, Việt Nam)
      Marker(
        point: const LatLng(16.5333, 112.0333),
        width: 146,
        height: 52,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFDE047), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '🇻🇳 QĐ. HOÀNG SA',
                style: TextStyle(
                  color: Color(0xFFFEF08A),
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
              ),
              Text(
                '(Đà Nẵng, Việt Nam)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
      // Quần đảo Trường Sa (Tỉnh Khánh Hòa, Việt Nam)
      Marker(
        point: const LatLng(9.5500, 114.0000),
        width: 146,
        height: 52,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFDC2626).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFDE047), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '🇻🇳 QĐ. TRƯỜNG SA',
                style: TextStyle(
                  color: Color(0xFFFEF08A),
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
              ),
              Text(
                '(Khánh Hòa, Việt Nam)',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// Tên nhà cung cấp bản đồ hiển thị huy hiệu / nguồn
  static String get mapProviderBadge =>
      hasVietmapKey ? '🗺️ Vietmap (Việt Nam)' : '🗺️ QĐ. Hoàng Sa & Trường Sa 🇻🇳';
}
