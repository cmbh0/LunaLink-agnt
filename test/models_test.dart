import 'package:flutter_test/flutter_test.dart';
import 'package:lunalink_agnt/models/ai_models.dart';
import 'package:lunalink_agnt/models/server_models.dart';

void main() {
  test('server profile json roundtrip', () {
    const p = ServerProfile(id: '1', name: 'srv', host: '127.0.0.1', username: 'root', password: 'x');
    final parsed = ServerProfile.fromJson(p.toJson());
    expect(parsed.host, '127.0.0.1');
    expect(parsed.port, 22);
  });

  test('ai config json roundtrip', () {
    const c = AiServiceConfig(id: '1', name: 'oai', provider: AiProviderType.openai, endpoint: 'https://api.example/v1', apiKey: 'k', model: 'm');
    final parsed = AiServiceConfig.fromJson(c.toJson());
    expect(parsed.provider, AiProviderType.openai);
    expect(parsed.model, 'm');
  });
}