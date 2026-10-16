import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/place_search_service.dart';
import '../services/map_sovereignty_helper.dart';

class HomeLocationMapScreen extends StatefulWidget {
  const HomeLocationMapScreen({super.key, this.initialPlace});

  final PlaceSuggestion? initialPlace;

  @override
  State<HomeLocationMapScreen> createState() => _HomeLocationMapScreenState();
}

class _HomeLocationMapScreenState extends State<HomeLocationMapScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  int _requestVersion = 0;
  List<PlaceSuggestion> _suggestions = const [];
  PlaceSuggestion? _selected;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialPlace?.latitude != null &&
            widget.initialPlace?.longitude != null
        ? widget.initialPlace : null;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    final version = ++_requestVersion;
    setState(() => _suggestions = const []);
    if (value.trim().length < 3) return;
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final results = await PlaceSearchService.search(value);
        if (mounted && version == _requestVersion) {
          setState(() => _suggestions = results);
        }
      } catch (_) {
        if (mounted && version == _requestVersion) {
          setState(() => _suggestions = const []);
        }
      }
    });
  }

  void _chooseSuggestion(PlaceSuggestion place) {
    if (place.latitude == null || place.longitude == null) return;
    _debounce?.cancel();
    _requestVersion++;
    _searchController.text = place.address;
    FocusScope.of(context).unfocus();
    _mapController.move(LatLng(place.latitude!, place.longitude!), 17);
    setState(() {
      _selected = place;
      _suggestions = const [];
      _resolving = false;
    });
  }

  Future<void> _placePin(LatLng point) async {
    final version = ++_requestVersion;
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    setState(() {
      _selected = PlaceSuggestion(
        '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
        latitude: point.latitude, longitude: point.longitude,
      );
      _suggestions = const [];
      _resolving = true;
    });
    try {
      final place = await PlaceSearchService.reverse(
        point.latitude, point.longitude);
      if (mounted && version == _requestVersion) {
        setState(() {
          _selected = place;
          _resolving = false;
        });
      }
    } catch (_) {
      if (mounted && version == _requestVersion) {
        setState(() => _resolving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = _selected;
    final center = initial?.latitude != null && initial?.longitude != null
        ? LatLng(initial!.latitude!, initial.longitude!)
        : const LatLng(16.0544, 108.2022);
    return Scaffold(
      appBar: AppBar(title: const Text('Chọn vị trí nhà trên bản đồ')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: initial == null ? 5.5 : 17,
              maxZoom: 19,
              onTap: (_, point) => _placePin(point),
            ),
            children: [
              MapSovereigntyHelper.buildTileLayer(),
              if (_selected?.latitude != null && _selected?.longitude != null)
                MarkerLayer(markers: [Marker(
                  point: LatLng(_selected!.latitude!, _selected!.longitude!),
                  width: 48,
                  height: 48,
                  alignment: Alignment.bottomCenter,
                  child: const Icon(Icons.location_pin, size: 48, color: Colors.red),
                )]),
              if (!MapSovereigntyHelper.hasVietmapKey)
                MarkerLayer(markers: MapSovereigntyHelper.buildSovereigntyMarkers()),
              SimpleAttributionWidget(
                source: Text(MapSovereigntyHelper.mapProviderBadge),
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: _search,
                    decoration: const InputDecoration(
                      hintText: 'Tìm địa chỉ hoặc địa điểm',
                      prefixIcon: Icon(Icons.search),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  if (_suggestions.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: ListView(
                        shrinkWrap: true,
                        children: _suggestions.map((place) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.place_outlined),
                          title: Text(place.address, maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                          onTap: () => _chooseSuggestion(place),
                        )).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 24,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_selected?.address ?? 'Chạm bản đồ để đặt ghim nhà',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (_resolving) const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _selected == null || _resolving
                          ? null : () => Navigator.pop(context, _selected),
                      icon: const Icon(Icons.check),
                      label: const Text('Chọn vị trí này'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
