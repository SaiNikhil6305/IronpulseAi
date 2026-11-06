import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A food from Open Food Facts (crowd-sourced, ODbL). Values are per 100 g/ml
/// as published; they are labelled as estimates in the app.
class FoodSearchResult {
  const FoodSearchResult({required this.name, this.brand, this.kcal100, this.protein100, this.carbs100, this.fat100});
  final String name;
  final String? brand;
  final double? kcal100;
  final double? protein100;
  final double? carbs100;
  final double? fat100;
}

class FoodSearchService {
  FoodSearchService([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: 'https://world.openfoodfacts.org',
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 12),
              headers: {'User-Agent': 'IronPulse/1.0 (Android; fitness tracker)'},
            ));
  final Dio _dio;

  static double? _n(Object? v) => v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);

  Future<List<FoodSearchResult>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    final res = await _dio.get<Map<String, dynamic>>('/cgi/search.pl', queryParameters: {
      'search_terms': q,
      'search_simple': 1,
      'action': 'process',
      'json': 1,
      'page_size': 20,
      'fields': 'product_name,brands,nutriments',
    });
    final products = (res.data?['products'] as List?) ?? const [];
    final out = <FoodSearchResult>[];
    for (final p in products) {
      final m = Map<String, dynamic>.from(p as Map);
      final name = (m['product_name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;
      final n = Map<String, dynamic>.from((m['nutriments'] as Map?) ?? const {});
      final r = FoodSearchResult(
        name: name,
        brand: (m['brands'] as String?)?.split(',').first.trim(),
        kcal100: _n(n['energy-kcal_100g']),
        protein100: _n(n['proteins_100g']),
        carbs100: _n(n['carbohydrates_100g']),
        fat100: _n(n['fat_100g']),
      );
      if (r.kcal100 == null && r.protein100 == null) continue; // no usable data
      out.add(r);
    }
    return out;
  }
}

final foodSearchProvider = Provider<FoodSearchService>((ref) => FoodSearchService());
