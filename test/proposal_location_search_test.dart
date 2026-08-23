import 'package:chargewise_my/modules/planning/services/proposal_location_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProposalLocationService locations;

  setUpAll(() async {
    locations = ProposalLocationService();
    await locations.load();
  });

  test('finds exact supported Malaysian places', () async {
    final kualaLumpur = await locations.search('Kuala Lumpur');
    final shahAlam = await locations.search('Shah Alam');

    expect(kualaLumpur.first.name, 'Kuala Lumpur');
    expect(kualaLumpur.first.state, 'Kuala Lumpur');
    expect(shahAlam.first.name, 'Shah Alam');
    expect(shahAlam.first.state, 'Selangor');
  });

  test('normalizes punctuation, repeated whitespace, and safe aliases',
      () async {
    final punctuation = await locations.search('  shah---alam  ');
    final alias = await locations.search('KL');

    expect(punctuation.first.name, 'Shah Alam');
    expect(alias.first.name, 'Kuala Lumpur');
  });

  test('returns no fabricated result for unsupported Sunway searches',
      () async {
    expect(await locations.search('Sunway'), isEmpty);
    expect(await locations.search('Bandar Sunway'), isEmpty);
  });

  test('limits suggestions and ignores incomplete queries', () async {
    expect(await locations.search('a', limit: 8), isEmpty);
    expect((await locations.search('city', limit: 6)).length,
        lessThanOrEqualTo(6));
  });
}
