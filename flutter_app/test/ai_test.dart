import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ironpulse/data/ai_repo.dart';
import 'package:ironpulse/data/db.dart';
import 'package:ironpulse/data/repo.dart';
import 'package:ironpulse/data/splits.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Map<String, dynamic> lastBody;
  late Map<String, String> lastHeaders;
  MockClient server(int status, Map<String, dynamic> resp) => MockClient((req) async {
        lastBody = jsonDecode(req.body) as Map<String, dynamic>;
        lastHeaders = req.headers;
        return http.Response(jsonEncode(resp), status, headers: {'content-type': 'application/json'});
      });

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await AppDb.resetForTests();
    await Repo.createProfile({'name': 'Nikhil', 'weekly_target': 3, 'goal': 'Build muscle'});
    await Repo.saveSplit('ppl', splitTemplates().first.days);
  });

  test('refuses to send without configuration (no fake answers)', () async {
    await AiRepo.saveConfig('http://127.0.0.1:8000', '');
    expect(() => AiRepo.send(null, 'hi', client: server(200, {'reply': 'x'})), throwsA(isA<AiException>()));
  });

  test('sends token, stores both messages locally', () async {
    await AiRepo.saveConfig('http://127.0.0.1:8000/', 'secret-token');
    final conv = await AiRepo.send(null, 'Explain progressive overload', client: server(200, {'reply': 'Add load over time.'}));
    expect(lastHeaders['authorization'], 'Bearer secret-token');
    final msgs = await AiRepo.messages(conv);
    expect(msgs.map((m) => m.role), ['user', 'assistant']);
    expect((await AiRepo.conversations()).single.title, 'Explain progressive overload');
  });

  test('no personal data is sent unless sharing is on, and never the name', () async {
    await AiRepo.saveConfig('http://127.0.0.1:8000', 'tok');
    await AiRepo.send(null, 'hi', client: server(200, {'reply': 'hey'}));
    expect(lastBody.containsKey('context'), isFalse);

    await AiRepo.saveSharing(true, false);
    await AiRepo.send(null, 'hi', client: server(200, {'reply': 'hey'}));
    final ctx = lastBody['context'] as String;
    expect(ctx, contains('Goal: Build muscle'));
    expect(ctx, contains('Push Day'));
    expect(ctx, isNot(contains('Nikhil')));
    expect(ctx, isNot(contains('Nutrition')));
  });

  test('server errors become clear messages and the question is kept for retry', () async {
    await AiRepo.saveConfig('http://127.0.0.1:8000', 'tok');
    await expectLater(
      AiRepo.send(null, 'hi', client: server(503, {'error': {'message': 'Is Ollama running? Start it with: ollama serve'}})),
      throwsA(predicate((e) => e is AiException && e.message.contains('ollama serve'))),
    );
    await expectLater(AiRepo.send(null, 'hi', client: server(401, {})),
        throwsA(predicate((e) => e is AiException && e.message.contains('token'))));
    final convs = await AiRepo.conversations();
    expect(convs, isNotEmpty);
    expect((await AiRepo.messages(convs.first.id)).last.role, 'user');
  });

  test('delete conversation and delete all', () async {
    await AiRepo.saveConfig('http://127.0.0.1:8000', 'tok');
    final a = await AiRepo.send(null, 'one', client: server(200, {'reply': 'r'}));
    await AiRepo.send(null, 'two', client: server(200, {'reply': 'r'}));
    await AiRepo.deleteConversation(a);
    expect((await AiRepo.conversations()).length, 1);
    expect(await AiRepo.messages(a), isEmpty);
    await AiRepo.deleteAll();
    expect(await AiRepo.conversations(), isEmpty);
  });
}
