import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';


class CacheService {
  static const Duration _cacheDuration = Duration(days: 7);

  // 🔹 Players Cache (General / Temporada / Históricos)
  static const String _playersCacheKey = 'cached_players';
  static const String _playersTemporadaCacheKey = 'cached_players_temporada';
  static const String _playersHistoricosCacheKey = 'cached_players_historicos';
  // 🔹 Temporadas Cache
  static const String _temporadasCacheKey = 'cached_temporadas';

  static Future<void> cacheTemporadas(List<dynamic> temporadas) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheData = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'data': temporadas,
    };
    await prefs.setString(_temporadasCacheKey, jsonEncode(cacheData));
  }

  static Future<List<dynamic>?> getCachedTemporadas() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_temporadasCacheKey);
    if (raw != null) {
      final decoded = jsonDecode(raw);
      final timestamp = decoded['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;
      const maxAge = 30 * 24 * 60 * 60 * 1000; // 30 días
      if ((now - timestamp) < Duration(days: 7).inMilliseconds) {
        return List<dynamic>.from(decoded['data']);
      }
    }
    return null;
  } 
  
  static Future<void> cachePlayers(List<dynamic> players) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheData = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'players': players,
    };
    await prefs.setString(_playersCacheKey, jsonEncode(cacheData));
  }

  static Future<List<dynamic>?> getCachedPlayers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playersCacheKey);

    if (raw != null) {
      final decoded = jsonDecode(raw);
      final timestamp = decoded['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;

      if ((now - timestamp) < _cacheDuration.inMilliseconds) {
        return List<dynamic>.from(decoded['players']);
      }
    }
    return null;
  }

  static Future<void> cachePlayersTemporada(List<dynamic> players) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheData = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'players': players,
    };
    await prefs.setString(_playersTemporadaCacheKey, jsonEncode(cacheData));
  }

  static Future<List<dynamic>?> getCachedPlayersTemporada() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playersTemporadaCacheKey);

    if (raw != null) {
      final decoded = jsonDecode(raw);
      final timestamp = decoded['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;

      if ((now - timestamp) < _cacheDuration.inMilliseconds) {
        return List<dynamic>.from(decoded['players']);
      }
    }
    return null;
  }

  static Future<void> cachePlayersHistoricos(List<dynamic> players) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheData = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'players': players,
    };
    await prefs.setString(_playersHistoricosCacheKey, jsonEncode(cacheData));
  }

  static Future<List<dynamic>?> getCachedPlayersHistoricos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_playersHistoricosCacheKey);

    if (raw != null) {
      final decoded = jsonDecode(raw);
      final timestamp = decoded['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;

      if ((now - timestamp) < _cacheDuration.inMilliseconds) {
        return List<dynamic>.from(decoded['players']);
      }
    }
    return null;
  }

  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_playersCacheKey);
  }

  // 🔹 Scorers Cache (General y por temporada)
  static const String _scorersCacheKey = 'cached_scorers';
  static String _scorersTemporadaKey(int temporadaId) => 'cached_scorers_$temporadaId';

  // Uso flexible
  static Future<void> cacheScorers(List<dynamic> scorers, [int? temporadaId]) {
    if (temporadaId != null) {
      return cacheScorersPorTemporada(temporadaId, scorers);
    } else {
      return cacheScorersGeneral(scorers);
    }
  }

  static Future<List<dynamic>?> getCachedScorers([int? temporadaId]) {
    if (temporadaId != null) {
      return getCachedScorersPorTemporada(temporadaId);
    } else {
      return getCachedScorersGeneral();
    }
  }

  // Versión sin temporada (general)
  static Future<void> cacheScorersGeneral(List<dynamic> scorers) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheData = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'scorers': scorers,
    };
    await prefs.setString(_scorersCacheKey, jsonEncode(cacheData));
  }

  static Future<List<dynamic>?> getCachedScorersGeneral() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scorersCacheKey);

    if (raw != null) {
      final decoded = jsonDecode(raw);
      final timestamp = decoded['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;

      if ((now - timestamp) < _cacheDuration.inMilliseconds) {
        return List<dynamic>.from(decoded['scorers']);
      }
    }
    return null;
  }

  // Versión por temporada
  static Future<void> cacheScorersPorTemporada(int temporadaId, List<dynamic> scorers) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheData = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'scorers': scorers,
    };
    await prefs.setString(_scorersTemporadaKey(temporadaId), jsonEncode(cacheData));
  }

  static Future<List<dynamic>?> getCachedScorersPorTemporada(int temporadaId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_scorersTemporadaKey(temporadaId));

    if (raw != null) {
      final decoded = jsonDecode(raw);
      final timestamp = decoded['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;

      if ((now - timestamp) < _cacheDuration.inMilliseconds) {
        return List<dynamic>.from(decoded['scorers']);
      }
    }
    return null;
  }

  static Future<void> clearScorersCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scorersCacheKey);
  }

  static Future<void> clearScorersTemporadaCache(int temporadaId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_scorersTemporadaKey(temporadaId));
  }

  static Future<void> clearAllCaches() async {
    final prefs = await SharedPreferences.getInstance();

    // Eliminar claves estáticas
    await prefs.remove(_playersCacheKey);
    await prefs.remove(_playersTemporadaCacheKey);
    await prefs.remove(_playersHistoricosCacheKey);
    await prefs.remove(_scorersCacheKey);

    // Eliminar partidos y equipos cacheados
    await prefs.remove('cache_partidos_jugados');
    await prefs.remove('cache_partidos_futuros');
    for (var key in prefs.getKeys()) {
      if (key.startsWith('cache_equipos_')) {
        await prefs.remove(key);
      }
    }

    // ⚠️ Eliminar claves dinámicas por temporada
    try {
      final uri = Uri.parse('https://entreredespadres.com.ar/wp-json/entre-redes/v1/temporadas');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final decoded = json.decode(res.body);
        final temporadas = decoded.values.toList();
        for (var temp in temporadas) {
          final id = temp['id'];
          if (id is int) {
            await prefs.remove(_scorersTemporadaKey(id));
            await prefs.remove(_imbatiblesTemporadaKey(id));
          }
        }
      }
    } catch (e) {
      debugPrint('No se pudieron eliminar claves dinámicas de goleadores por temporada: $e');
    }
  }
  // 🔹 Imbatibles Cache (por temporada)
  static String _imbatiblesTemporadaKey(int temporadaId) => 'cached_imbatibles_$temporadaId';

  static Future<void> cacheImbatiblesPorTemporada(int temporadaId, List<dynamic> arqueros) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheData = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'arqueros': arqueros,
    };
    await prefs.setString(_imbatiblesTemporadaKey(temporadaId), jsonEncode(cacheData));
  }

  static Future<List<dynamic>?> getCachedImbatiblesPorTemporada(int temporadaId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_imbatiblesTemporadaKey(temporadaId));

    if (raw != null) {
      final decoded = jsonDecode(raw);
      final timestamp = decoded['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;

      if ((now - timestamp) < _cacheDuration.inMilliseconds) {
        return List<dynamic>.from(decoded['arqueros']);
      }
    }
    return null;
  }

  static Future<List<dynamic>?> getCachedPlayersPorEquipo(int equipoId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'cached_players_equipo_$equipoId';
    final raw = prefs.getString(key);

    if (raw != null) {
      final decoded = jsonDecode(raw);
      final timestamp = decoded['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;
      if ((now - timestamp) < Duration(days: 3).inMilliseconds) {
        return List<dynamic>.from(decoded['players']);
      }
    }
    return null;
  }

  static Future<void> clearCacheOncePerWeekWindow() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final lastClearIso = prefs.getString('ultima_limpieza_cache');

    // Convertir última limpieza a DateTime si existe
    final lastClear = lastClearIso != null ? DateTime.tryParse(lastClearIso) : null;

    // 📅 Buscar el último sábado a las 19:00 antes de ahora
    DateTime ultimoSabado = now.subtract(Duration(days: (now.weekday % 7)));
    ultimoSabado = DateTime(
      ultimoSabado.year,
      ultimoSabado.month,
      ultimoSabado.day,
      21,
    );

    // Si todavía no pasó este sábado a las 21h, restamos 7 días
    if (now.isBefore(ultimoSabado)) {
      ultimoSabado = ultimoSabado.subtract(const Duration(days: 7));
    }

    // Si la última limpieza fue antes del último sábado a las 21h ⇒ limpiar
    if (lastClear == null || lastClear.isBefore(ultimoSabado)) {
      // 🔥 Eliminar claves fijas
      await prefs.remove(_playersCacheKey);
      await prefs.remove(_playersTemporadaCacheKey);
      await prefs.remove(_playersHistoricosCacheKey);
      await prefs.remove(_temporadasCacheKey);

      // 🔥 Eliminar claves dinámicas por prefijo
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('scorers_temporada_') ||
            key.startsWith('imbatibles_temporada_') ||
            key.startsWith('equipos_temporada_') ||
            key.startsWith('matches_filtros_') ||
            key.startsWith('standings_temporada_')) {
          await prefs.remove(key);
        }
      }

      await prefs.setString('ultima_limpieza_cache', now.toIso8601String());
      debugPrint('🧹 Caché eliminada en la ventana semanal post sábado 19h');
    }
  }

  // 🔹 Clave para partidos jugados por temporada
  static String _partidosJugadosTemporadaKey(int temporadaId) =>
      'cached_partidos_jugados_$temporadaId';

  static Future<void> cachePartidosJugadosPorTemporada(
      int temporadaId, List<dynamic> partidos) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheData = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'partidos': partidos,
    };
    await prefs.setString(
        _partidosJugadosTemporadaKey(temporadaId), jsonEncode(cacheData));
  }

  static Future<List<dynamic>?> getCachedPartidosJugadosPorTemporada(
      int temporadaId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_partidosJugadosTemporadaKey(temporadaId));

    if (raw != null) {
      final decoded = jsonDecode(raw);
      final timestamp = decoded['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;

      if ((now - timestamp) < _cacheDuration.inMilliseconds) {
        return List<dynamic>.from(decoded['partidos']);
      }
    }
    return null;
  }
}