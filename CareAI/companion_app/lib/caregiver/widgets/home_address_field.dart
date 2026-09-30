import 'dart:async';

import 'package:flutter/material.dart';

import '../services/place_search_service.dart';
import '../screens/home_location_map_screen.dart';

class HomeAddressField extends StatefulWidget {
  const HomeAddressField({
    super.key,
    this.initialValue = '',
    this.initialLatitude,
    this.initialLongitude,
    required this.onChanged,
    required this.onPlaceSelected,
  });

  final String initialValue;
  final double? initialLatitude;
  final double? initialLongitude;
  final ValueChanged<String> onChanged;
  final ValueChanged<PlaceSuggestion?> onPlaceSelected;

  @override
  State<HomeAddressField> createState() => _HomeAddressFieldState();
}

class _HomeAddressFieldState extends State<HomeAddressField> {
  late final TextEditingController _controller;
  Timer? _debounce;
  int _searchVersion = 0;
  List<PlaceSuggestion> _suggestions = const [];
  bool _loading = false;
  bool _failed = false;
  bool _hasSearched = false;
  PlaceSuggestion? _selectedPlace;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    if (widget.initialLatitude != null && widget.initialLongitude != null) {
      _selectedPlace = PlaceSuggestion(widget.initialValue,
        latitude: widget.initialLatitude, longitude: widget.initialLongitude);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchVersion++;
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    widget.onChanged(value);
    _selectedPlace = null;
    widget.onPlaceSelected(null);
    _debounce?.cancel();
    final version = ++_searchVersion;
    final query = value.trim();
    setState(() {
      _suggestions = const [];
      _loading = query.length >= 3;
      _failed = false;
      _hasSearched = false;
    });
    if (query.length < 3) return;

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final results = await PlaceSearchService.search(query);
        if (!mounted || version != _searchVersion) return;
        setState(() {
          _suggestions = results;
          _loading = false;
          _hasSearched = true;
        });
      } catch (_) {
        if (!mounted || version != _searchVersion) return;
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    });
  }

  void _select(PlaceSuggestion suggestion) {
    _debounce?.cancel();
    _searchVersion++;
    _controller.text = suggestion.address;
    widget.onChanged(suggestion.address);
    _selectedPlace = suggestion;
    widget.onPlaceSelected(suggestion);
    FocusScope.of(context).unfocus();
    setState(() {
      _suggestions = const [];
      _loading = false;
      _failed = false;
      _hasSearched = false;
    });
  }

  Future<void> _openMap() async {
    final chosen = await Navigator.push<PlaceSuggestion>(
      context,
      MaterialPageRoute(builder: (_) => HomeLocationMapScreen(
        initialPlace: _selectedPlace,
      )),
    );
    if (chosen != null && mounted) _select(chosen);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Địa chỉ nhà để cứu hộ',
            hintText: 'Nhập tên đường, số nhà hoặc địa điểm',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
        if (_loading) const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(),
        ),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          ..._suggestions.map((suggestion) => ListTile(
            dense: true,
            leading: const Icon(Icons.place_outlined),
            title: Text(suggestion.address, maxLines: 2,
              overflow: TextOverflow.ellipsis),
            onTap: () => _select(suggestion),
          )),
          const Text('Gợi ý từ OpenStreetMap / Photon',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
        ],
        if (_failed) const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Không tải được gợi ý. Bạn vẫn có thể nhập địa chỉ thủ công.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        if (_hasSearched && _suggestions.isEmpty) const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Không tìm thấy địa điểm. Bạn có thể nhập tay hoặc chọn trên bản đồ.',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openMap,
          icon: const Icon(Icons.map_outlined),
          label: const Text('Chọn chính xác trên bản đồ'),
        ),
        if (_selectedPlace?.latitude != null)
          const Text('Đã chọn vị trí có ghim trên bản đồ',
            style: TextStyle(fontSize: 12, color: Colors.green)),
      ],
    );
  }
}
