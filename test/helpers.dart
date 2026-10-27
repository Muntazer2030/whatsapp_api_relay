import 'dart:convert';

import 'package:relay_native/services.dart';

class MemoryRepository implements Repository {
  Map<String, dynamic> state = {}, secrets = {};
  bool failOnAttempt = false;
  @override
  Future<Map<String, dynamic>> load() async =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(state)));
  @override
  Future<void> save(Map<String, dynamic> data) async {
    if (failOnAttempt &&
        (data['runs'] as List).any((r) => (r['attempts'] as Map).isNotEmpty)) {
      throw StateError('Disk full');
    }
    state = Map<String, dynamic>.from(jsonDecode(jsonEncode(data)));
  }

  @override
  Future<Map<String, dynamic>> loadSecrets() async => secrets;
  @override
  Future<void> saveSecrets(Map<String, String> data) async {
    secrets = Map<String, dynamic>.from(data);
  }
}
