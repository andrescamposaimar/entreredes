import 'cache_service.dart';
import 'api_service.dart';

class PartidosCache {
  static final PartidosCache _instance = PartidosCache._internal();

  factory PartidosCache() => _instance;

  PartidosCache._internal();

  List<dynamic> partidosJugados = [];

  Future<List<dynamic>> getPartidosJugados(int temporadaId) async {
    if (partidosJugados.isNotEmpty) return partidosJugados;

    // 1. Buscar en SharedPreferences
    final cached = await CacheService.getCachedPartidosJugadosPorTemporada(temporadaId);
    if (cached != null) {
      partidosJugados = cached;
      return partidosJugados;
    }

    // 2. Si no está cacheado, traer de la API
    final res = await ApiService.getPartidos(
      temporada: temporadaId,
      page: 1,
      perPage: 500,
    );
    partidosJugados = res['items']?.where((p) => p['status'] == 'publish').toList() ?? [];

    // Guardar en cache persistente
    await CacheService.cachePartidosJugadosPorTemporada(temporadaId, partidosJugados);

    return partidosJugados;
  }
}