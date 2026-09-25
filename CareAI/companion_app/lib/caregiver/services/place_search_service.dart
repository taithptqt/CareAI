import 'dart:convert';

import 'package:http/http.dart' as http;

class PlaceSuggestion {
  const PlaceSuggestion(this.address, {this.latitude, this.longitude});

  final String address;
  final double? latitude;
  final double? longitude;
}

class PlaceSearchService {
  // A separate Photon instance can be supplied for deployments with more traffic.
  static const _endpoint = String.fromEnvironment(
    'CAREAI_PLACE_SEARCH_URL',
    defaultValue: 'https://photon.komoot.io/api/',
  );

  static Future<List<PlaceSuggestion>> search(String query) async {
    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'q': query.trim(),
      'limit': '10',
      'countrycode': 'VN',
    });
    final response = await http.get(uri).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) {
      throw Exception('Không thể tải gợi ý địa điểm');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final features = data['features'] as List<dynamic>? ?? const [];
    final suggestions = <PlaceSuggestion>[];
    final addresses = <String>{};
    for (final feature in features) {
      if (feature is! Map<String, dynamic>) continue;
      final properties = feature['properties'];
      if (properties is! Map<String, dynamic>) continue;
      final address = _formatAddress(properties);
      if (address.isEmpty || !addresses.add(address)) continue;
      final geometry = feature['geometry'];
      final coordinates = geometry is Map<String, dynamic>
          ? geometry['coordinates'] : null;
      final longitude = coordinates is List && coordinates.length >= 2
          ? (coordinates[0] as num?)?.toDouble() : null;
      final latitude = coordinates is List && coordinates.length >= 2
          ? (coordinates[1] as num?)?.toDouble() : null;
      suggestions.add(PlaceSuggestion(address,
        latitude: latitude, longitude: longitude));
    }
    return suggestions;
  }

  static Future<PlaceSuggestion> reverse(double latitude, double longitude) async {
    final uri = Uri.parse(_endpoint).replace(
      path: Uri.parse(_endpoint).path.replaceFirst(RegExp(r'/api/?$'), '/reverse'),
      queryParameters: {
        'lat': latitude.toString(),
        'lon': longitude.toString(),
        'limit': '1',
      },
    );
    final response = await http.get(uri).timeout(const Duration(seconds: 6));
    if (response.statusCode != 200) {
      throw Exception('Không thể lấy địa chỉ tại ghim');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final features = data['features'] as List<dynamic>? ?? const [];
    if (features.isEmpty) {
      return PlaceSuggestion('$latitude, $longitude',
        latitude: latitude, longitude: longitude);
    }
    final properties = (features.first as Map<String, dynamic>)['properties'];
    final address = properties is Map<String, dynamic>
        ? _formatAddress(properties) : '';
    return PlaceSuggestion(address.isEmpty ? '$latitude, $longitude' : address,
      latitude: latitude, longitude: longitude);
  }

  static String _formatAddress(Map<String, dynamic> properties) {
    String value(String key) => (properties[key] as String? ?? '').trim();

    final street = [value('housenumber'), value('street')]
        .where((part) => part.isNotEmpty).join(' ');
    final parts = <String>[
      value('name'),
      street,
      value('district'),
      value('city'),
      value('state'),
      value('country'),
    ];
    final unique = <String>[];
    for (final part in parts) {
      if (part.isNotEmpty &&
          !unique.any((existing) => existing.toLowerCase() == part.toLowerCase())) {
        unique.add(part);
      }
    }
    return unique.join(', ');
  }
}
