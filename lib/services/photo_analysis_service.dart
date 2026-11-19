import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Resultat de lecture d'une carte grise / plaque VIN.
class VinReading {
  final String? vin;
  final String? brand;
  final String? model;
  final int? year;
  final String? engine;
  final String confidence; // high | medium | low
  final String? note;

  const VinReading({
    this.vin,
    this.brand,
    this.model,
    this.year,
    this.engine,
    this.confidence = 'low',
    this.note,
  });

  factory VinReading.fromJson(Map<String, dynamic> j) => VinReading(
        vin: j['vin'] as String?,
        brand: j['brand'] as String?,
        model: j['model'] as String?,
        year: (j['year'] as num?)?.toInt(),
        engine: j['engine'] as String?,
        confidence: (j['confidence'] ?? 'low') as String,
        note: j['note'] as String?,
      );
}

/// Resultat d'identification d'une piece.
class PartReading {
  final bool isAutoPart;
  final String? category;
  final String? catalogMatch;
  final String? partName;
  final String? oemPartNumber;
  final String? sideOrPosition;
  final String confidence;
  final String? note;

  const PartReading({
    this.isAutoPart = false,
    this.category,
    this.catalogMatch,
    this.partName,
    this.oemPartNumber,
    this.sideOrPosition,
    this.confidence = 'low',
    this.note,
  });

  factory PartReading.fromJson(Map<String, dynamic> j) => PartReading(
        isAutoPart: (j['is_auto_part'] ?? false) as bool,
        category: j['category'] as String?,
        catalogMatch: j['catalog_match'] as String?,
        partName: j['part_name'] as String?,
        oemPartNumber: j['oem_part_number'] as String?,
        sideOrPosition: j['side_or_position'] as String?,
        confidence: (j['confidence'] ?? 'low') as String,
        note: j['note'] as String?,
      );
}

/// Erreur lisible par le client.
class PhotoAnalysisException implements Exception {
  final String message;
  const PhotoAnalysisException(this.message);
  @override
  String toString() => message;
}

/// Envoie une photo a la fonction serveur `analyze-photo` (IA).
/// Exige une session (client ou invite) : le quota est compte par compte.
class PhotoAnalysisService {
  final SupabaseClient _client;
  PhotoAnalysisService(this._client);

  static String mediaTypeFor(String fileName, String? mimeType) {
    if (mimeType != null && mimeType.startsWith('image/')) return mimeType;
    final ext = fileName.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'image/jpeg',
    };
  }

  Future<VinReading> readVin(Uint8List bytes, String mediaType) async {
    final data = await _invoke({'kind': 'vin'}, bytes, mediaType);
    return VinReading.fromJson(data);
  }

  Future<PartReading> readPart(
    Uint8List bytes,
    String mediaType, {
    required Map<String, List<String>> catalog,
  }) async {
    final data =
        await _invoke({'kind': 'part', 'catalog': catalog}, bytes, mediaType);
    return PartReading.fromJson(data);
  }

  Future<Map<String, dynamic>> _invoke(
    Map<String, dynamic> extra,
    Uint8List bytes,
    String mediaType,
  ) async {
    try {
      final res = await _client.functions.invoke('analyze-photo', body: {
        ...extra,
        'media_type': mediaType,
        'image_base64': base64Encode(bytes),
      });
      final data = res.data;
      if (data is Map && data['result'] is Map) {
        return Map<String, dynamic>.from(data['result'] as Map);
      }
      throw const PhotoAnalysisException(
          'Lecture impossible. Saisissez les informations à la main.');
    } on FunctionException catch (e) {
      final code = (e.details is Map) ? (e.details as Map)['error'] : null;
      throw PhotoAnalysisException(switch (code) {
        'quota_exceeded' =>
          'Limite de lectures de photos atteinte pour aujourd\'hui. '
              'Saisissez les informations à la main.',
        'image_too_large' => 'Photo trop lourde. Réessayez avec une autre photo.',
        'unreadable' => 'Photo illisible. Essayez une photo plus nette.',
        _ => 'Lecture indisponible pour le moment. '
            'Saisissez les informations à la main.',
      });
    }
  }
}
