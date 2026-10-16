import 'api_client.dart';

/// Référentiel linguistique (public) : langues + dialectes.
class ReferentialApi {
  final ApiClient _client;
  ReferentialApi([ApiClient? client]) : _client = client ?? ApiClient();

  Future<List<Map<String, dynamic>>> languages() async {
    final data = await _client.get('/api/languages') as Map;
    final list = data['languages'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> dialects({String? lang}) async {
    final q = lang != null && lang.isNotEmpty ? '?lang=${Uri.encodeComponent(lang)}' : '';
    final data = await _client.get('/api/dialects$q') as Map;
    final list = data['dialects'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}
