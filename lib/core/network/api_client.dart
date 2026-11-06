import 'package:dio/dio.dart';

import '../config/env.dart';

/// Normalised API failure, built from the backend's
/// `{"error": {"code", "message", "details"}}` envelope.
class ApiException implements Exception {
  ApiException(this.message, {this.code = 'unknown', this.status, this.details});

  final String message;
  final String code;
  final int? status;
  final Object? details;

  /// Network problems, timeouts, 5xx and rate limits can be retried later.
  bool get isTransient =>
      status == null || status == 408 || status == 429 || (status != null && status! >= 500);

  bool get isAuth => status == 401;

  @override
  String toString() => message;

  static ApiException from(Object error) {
    if (error is ApiException) return error;
    if (error is DioException) {
      final res = error.response;
      if (res == null) {
        return ApiException(
          error.type == DioExceptionType.connectionTimeout || error.type == DioExceptionType.receiveTimeout
              ? 'The server took too long to respond.'
              : 'No connection to IronPulse servers. Your data is saved on this device.',
          code: 'network',
        );
      }
      final data = res.data;
      if (data is Map && data['error'] is Map) {
        final e = data['error'] as Map;
        return ApiException('${e['message'] ?? 'Request failed.'}',
            code: '${e['code'] ?? 'http_error'}', status: res.statusCode, details: e['details']);
      }
      return ApiException('Request failed (${res.statusCode}).', code: 'http_error', status: res.statusCode);
    }
    return ApiException(error.toString());
  }
}

typedef TokenProvider = Future<String?> Function({bool forceRefresh});

/// Thin Dio wrapper that attaches the Supabase access token and retries once
/// with a refreshed token when the backend reports an expired session.
class ApiClient {
  ApiClient({required TokenProvider tokenProvider, Dio? dio, String? baseUrl})
      : _token = tokenProvider,
        dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl ?? Env.apiBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 45),
              sendTimeout: const Duration(seconds: 20),
              contentType: 'application/json',
            )) {
    this.dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      final token = await _token(forceRefresh: options.extra['refreshed'] == true);
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    }, onError: (e, handler) async {
      final opts = e.requestOptions;
      if (e.response?.statusCode == 401 && opts.extra['refreshed'] != true) {
        opts.extra['refreshed'] = true;
        try {
          final res = await this.dio.fetch(opts);
          return handler.resolve(res);
        } on DioException catch (err) {
          return handler.next(err);
        }
      }
      handler.next(e);
    }));
  }

  final Dio dio;
  final TokenProvider _token;

  Future<dynamic> request(String method, String path, {Object? body, Map<String, dynamic>? query}) async {
    try {
      final res = await dio.request<dynamic>(path,
          data: body, queryParameters: query, options: Options(method: method));
      return res.data;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => request('GET', path, query: query);
  Future<dynamic> put(String path, Object? body) => request('PUT', path, body: body);
  Future<dynamic> post(String path, Object? body) => request('POST', path, body: body);
  Future<dynamic> delete(String path) => request('DELETE', path);
}
