import 'package:flutter_test/flutter_test.dart';
import 'package:teranga_parts/core/config/parts_config.dart';
import 'package:teranga_parts/features/admin/sourcing_helpers.dart';
import 'package:teranga_parts/models/parts_request.dart';

void main() {
  const req = PartsRequest(
    id: 'r1',
    clientId: 'c1',
    partName: 'Plaquettes de frein avant',
    vehicleBrand: 'Hyundai',
    vehicleModel: 'Tucson',
    vehicleYear: 2018,
    vehicleVin: 'KMHJ381ABJU123456',
    notes: 'Bruit au freinage\nRéf. lue sur la photo : 58101-2SA70\n'
        'Position : avant',
  );

  test('référence lue par l\'IA retrouvée dans les précisions', () {
    expect(oemRefFromNotes(req.notes), '58101-2SA70');
    expect(oemRefFromNotes('rien'), isNull);
    expect(oemRefFromNotes(null), isNull);
  });

  test('message fournisseur en anglais avec référence et VIN', () {
    final m = supplierMessageEn(req, reference: '58101-2SA70');
    expect(m, contains('OEM part number: 58101-2SA70'));
    expect(m, contains('VIN: KMHJ381ABJU123456'));
    expect(m, contains('Hyundai Tucson (2018)'));
    expect(supplierMessageEn(req), isNot(contains('OEM part number')));
  });

  test('liens de recherche fournisseurs', () {
    final crdi = PartsConfig.suppliers.firstWhere((s) => s.id == 'crdi');
    final spare =
        PartsConfig.suppliers.firstWhere((s) => s.id == 'sparekorea');
    expect(crdi.urlFor('58101-2SA70'),
        'https://crdi.online/search?q=58101-2SA70');
    expect(spare.urlFor(''), 'https://sparekorea.com');
    expect(spare.urlFor('58101-2SA70'),
        startsWith('https://www.google.com/search?q=site%3Asparekorea.com'));
    expect(PartsConfig.vinCatalogUrl(' KMHJ381ABJU123456 '),
        'https://partsouq.com/en/search/all?q=KMHJ381ABJU123456');
  });

  test('historique : même référence d\'abord, puis même pièce/modèle', () {
    Map<String, dynamic> row(String? ref, String part, String model,
            String date) =>
        {
          'part_ref': ref,
          'source': 'seoul_autoparts',
          'buy_price_krw': 45000,
          'weight_kg': 1.2,
          'available': true,
          'created_at': date,
          'parts_requests': {
            'part_name': part,
            'vehicle_brand': 'Hyundai',
            'vehicle_model': model,
            'vehicle_year': 2019,
          },
        };
    final rows = [
      row(null, 'Plaquettes de frein avant', 'tucson', '2026-11-10'),
      row('581012SA70', 'Plaquettes', 'Santa Fe', '2026-11-01'),
      row('99999-00000', 'Filtre', 'Tucson', '2026-11-15'),
    ];
    final out = pastSourcingsFrom(rows,
        const HistoryKey('r1', '58101-2SA70', 'Plaquettes de frein avant',
            'Tucson'));
    expect(out.length, 2);
    expect(out.first.sameRef, isTrue);
    expect(out.first.vehicle, 'Hyundai Santa Fe (2019)');
    expect(out.last.sameRef, isFalse);
  });
}
