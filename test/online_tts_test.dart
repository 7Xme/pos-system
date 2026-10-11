import 'package:bookstore_pos/core/tts/online_tts_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('OnlineTtsService (بدون SAPI)', () {
    test('fetchAudio يُرجع بايتات الصوت عند نجاح الخادم', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        expect(req.url.host, 'translate.google.com');
        expect(req.url.queryParameters['tl'], 'ar');
        expect(req.url.queryParameters['client'], 'tw-ob');
        return http.Response.bytes([1, 2, 3, 4], 200);
      });
      final bytes = await OnlineTtsService.fetchAudio(
        'مرحبا',
        client: client,
      );
      expect(bytes, [1, 2, 3, 4]);
      expect(calls, 1);
    });

    test('fetchAudio يُرجع null عند خطأ الخادم', () async {
      final client = MockClient(
        (_) async => http.Response('nope', 404),
      );
      expect(
        await OnlineTtsService.fetchAudio('مرحبا', client: client),
        isNull,
      );
    });

    test('fetchAudio لا يطلب الشبكة لنص فارغ', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response.bytes([1], 200);
      });
      expect(await OnlineTtsService.fetchAudio('  ', client: client), isNull);
      expect(calls, 0);
    });

    test('fetchAudio لا يرمي عند عطل الشبكة', () async {
      final client = MockClient((_) async {
        throw Exception('network down');
      });
      expect(
        await OnlineTtsService.fetchAudio('مرحبا', client: client),
        isNull,
      );
    });
  });
}
