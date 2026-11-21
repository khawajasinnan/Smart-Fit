import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartfit/features/chatbot/data/services/chatbot_api_service.dart';

import '../../helpers/fake_dio_adapter.dart';

void main() {
  test('sends message, contexts and images; returns text + search trigger', () async {
    final adapter = FakeDioAdapter((_) => {
          'reply': 'Theek hai!',
          'search': {'garment': 'kurta'},
          'search_raw': '{"garment": "kurta"}',
          'model': 'gemini-2.5-flash',
        });
    final service = ChatbotApiService(fakeDio(adapter));

    final reply = await service.sendMessage(
      'black kurta',
      profileContext: 'gender: male',
      chatContext: 'User: hi',
      images: [ChatImageInput(bytes: Uint8List.fromList([1, 2, 3]), mimeType: 'image/jpeg')],
    );

    expect(reply.text, 'Theek hai!');
    expect(reply.searchRaw, '{"garment": "kurta"}');

    final sent = adapter.requests.single;
    expect(sent.path, '/chat');
    final data = sent.data as Map<String, dynamic>;
    expect(data['message'], 'black kurta');
    expect(data['profile_context'], 'gender: male');
    expect(data['chat_context'], 'User: hi');
    expect(data['images'], [
      {'mime_type': 'image/jpeg', 'data_base64': 'AQID'},
    ]);
    expect(data['history'], isEmpty);
  });

  test('keeps a rolling history including the search trigger, and can reset', () async {
    final adapter = FakeDioAdapter((_) => {'reply': 'ok', 'search_raw': '{"g": 1}'});
    final service = ChatbotApiService(fakeDio(adapter));

    for (var i = 0; i < 10; i++) {
      await service.sendMessage('msg $i');
    }
    final history = (adapter.requests.last.data as Map<String, dynamic>)['history'] as List;
    expect(history.length, 16); // capped
    expect(history.last, {'role': 'model', 'text': 'ok\n[SMARTFIT_SEARCH: {"g": 1}]'});

    service.resetChat();
    await service.sendMessage('fresh');
    expect((adapter.requests.last.data as Map<String, dynamic>)['history'], isEmpty);
  });

  test('server errors become friendly chat text', () async {
    final adapter = FakeDioAdapter((_) => {
          'error': {'code': 'RATE_LIMITED', 'message': 'busy'},
        })..status = 429;
    final reply = await ChatbotApiService(fakeDio(adapter)).sendMessage('hi');
    expect(reply.text, contains('busy right now'));
    expect(reply.searchRaw, isNull);
  });
}
