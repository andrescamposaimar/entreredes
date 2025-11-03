import 'dart:convert';
import 'package:http/http.dart' as http;
import 'cache_service.dart';
import 'api_service.dart';

class RemoteDataService {
  static const _adsUrl = 'https://entreredespadres.com.ar/wp-content/uploads/media/publicidades.json';
  static const _listasUrl = 'https://entreredespadres.com.ar/wp-content/uploads/media/listas_jugadores.json';

  static Future<Map<String, String>> fetchAdImages() async {
    try {
      final res = await http.get(Uri.parse(_adsUrl));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return {
          'estadisticas': data['estadisticas_ad'] ?? '',
          'alineaciones': data['alineaciones_ad'] ?? '',
          'jugadores': data['jugadores_ad'] ?? '',
          'equipos': data['equipos_ad'] ?? '',
          'tabla': data['tabla_ad'] ?? '',
          'goleadores': data['goleadores_ad'] ?? '',
          'imbatibles': data['imbatibles_ad'] ?? '',
          'zocalo': data['zocalo_ad'] ?? '',
        };
      }
    } catch (e) {
      print('❌ Error al cargar publicidades: $e');
    }
    return {
      'estadisticas': '',
      'alineaciones': '',
      'jugadores': '',
      'equipos': '',
      'tabla': ''
    };
  }

  static Future<Map<String, List<int>>> fetchListasJugadores() async {
    try {
      final res = await http.get(Uri.parse(_listasUrl));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return {
          'espera': List<int>.from(data['lista_espera'] ?? []),
          'reserva': List<int>.from(data['lista_reserva'] ?? []),
        };
      }
    } catch (e) {
      print('❌ Error al cargar listas de jugadores: $e');
    }
    return {'espera': [], 'reserva': []};
  }

  Future<List<Map<String, dynamic>>> obtenerResultadosLive() async {
    final url = Uri.parse(
      'https://script.google.com/macros/s/AKfycbxyf-7EOR3CX10ZEpg6TZyIXv2qVtxWhp85Gs1LvGOM_IpkXxLJtprgubDX9UEJItBCvQ/exec?op=consultar',
    );

    final response = await http.get(url);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.cast<Map<String, dynamic>>();
    } else {
      throw Exception('Error al obtener resultados en vivo');
    }
  }

  static Future<int?> getTemporadaIdPorNombre(String nombre) async {
    final cached = await CacheService.getCachedTemporadas();
    if (cached != null) {
      final match = cached.firstWhere(
        (t) => t['name'].toString().contains(nombre),
        orElse: () => null,
      );
      if (match != null) return match['id'];
    }

    final nuevas = await ApiService.getTemporadas();
    await CacheService.cacheTemporadas(nuevas);

    final match = nuevas.firstWhere(
      (t) => t['name'].toString().contains(nombre),
      orElse: () => null,
    );
    if (match != null) return match['id'];

    return null;
  }

  static Future<List<AdItem>> fetchZocaloAds() async {
    try {
      final res = await http.get(Uri.parse(_adsUrl));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final List<dynamic> items = data['zocalo_ads'] ?? [];
        return items
            .map((item) => AdItem(
                  imageUrl: item['image'] ?? '',
                  link: item['link'] ?? '',
                ))
            .where((ad) => ad.imageUrl.isNotEmpty && ad.link.isNotEmpty)
            .toList();
      }
    } catch (e) {
      print('❌ Error al cargar zócalo carrusel: $e');
    }
    return [];
  }
}

class AdItem {
  final String imageUrl;
  final String link;

  const AdItem({required this.imageUrl, required this.link});
}