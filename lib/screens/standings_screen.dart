import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'package:flutter/rendering.dart';
import '../services/remote_data_service.dart';
import '../widgets/zocalo_publicitario.dart';
import '../services/partidos_cache.dart';
import '../services/cache_service.dart';



class StandingsScreen extends StatefulWidget {
  const StandingsScreen({super.key});

  @override
  State<StandingsScreen> createState() => _StandingsScreenState();
}

class _StandingsScreenState extends State<StandingsScreen> {
  List<dynamic> posiciones = [];
  List<dynamic> todasLasPosiciones = [];
  List<String> titulosDisponibles = [];
  List<dynamic> temporadas = [];

  int? temporadaSeleccionadaId;
  String? nombreTemporadaSeleccionada = '2025';
  String? tituloSeleccionado;
  String? tablaAdUrl;

  int currentPage = 1;
  final int perPage = 20;
  bool isLoading = false;
  bool hasMore = true;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _loadTemporadas();
  }

  Future<void> _cargarPartidosTemporadaSeleccionada() async {
    await PartidosCache().getPartidosJugados(temporadaSeleccionadaId!);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 &&
        !isLoading && hasMore) {
      _fetchTablas();
    }
  }

  Future<void> _loadTemporadas() async {
    try {
      final data = await ApiService.getTemporadas();
      setState(() => temporadas = data);

      final match = data.firstWhere(
        (t) => t['name'].toString().contains(nombreTemporadaSeleccionada!),
        orElse: () => null,
      );

      if (match != null) {
        temporadaSeleccionadaId = match['id'];
      }

      await _cargarPartidosTemporadaSeleccionada();
      await _obtenerPartidosTemporada();
      await _loadTablasDesdeCache();
      await _fetchTablas();
    } catch (e) {
      debugPrint('❌ Error al cargar temporadas: $e');
    }
  }

  void _resetAndFetch() async {
    setState(() {
      posiciones.clear();
      todasLasPosiciones.clear();
      titulosDisponibles.clear();
      tituloSeleccionado = null;
      currentPage = 1;
      hasMore = true;
    });
    
    await _obtenerPartidosTemporada();
    await _loadTablasDesdeCache();
    await _fetchTablas();
  }

  Future<void> _fetchTablas() async {
    if (!hasMore || isLoading) return;

    setState(() => isLoading = true);

    try {
      final response = await ApiService.getTablas(
        temporada: temporadaSeleccionadaId?.toString(),
        page: currentPage,
        perPage: perPage,
      );
      final List<dynamic> nuevasTablas = response['items'] ?? [];

      if (currentPage == 1 && nuevasTablas.isNotEmpty) {
        await _guardarCacheTablas(nuevasTablas);
      }

      final Map<String, dynamic> uniqueTables = {};
      for (var tabla in todasLasPosiciones) {
        uniqueTables[tabla['titulo'] ?? ''] = tabla;
      }

      for (var tabla in nuevasTablas) {
        if (!uniqueTables.containsKey(tabla['titulo'] ?? '')) {
          uniqueTables[tabla['titulo'] ?? ''] = tabla;
        }
      }

      final nuevasTodas = uniqueTables.values.toList();
      final nuevosTitulos = nuevasTodas
          .map<String>((tabla) => tabla['titulo']?.toString() ?? 'Sin título')
          .toSet()
          .toList();

      nuevosTitulos.sort((a, b) {
        int prioridad(String titulo) {
          final lower = titulo.toLowerCase();
          if (lower.contains('clausura')) return 0;
          if (lower.contains('apertura')) return 1;
          if (lower.contains('clasificacion')) return 2;
          return 3;
        }

        final p1 = prioridad(a);
        final p2 = prioridad(b);
        return (p1 != p2) ? p1.compareTo(p2) : a.compareTo(b);
      });

      setState(() {
        currentPage++;
        todasLasPosiciones = nuevasTodas;
        titulosDisponibles = nuevosTitulos;
        if (tituloSeleccionado == null && nuevosTitulos.isNotEmpty) {
          tituloSeleccionado = nuevosTitulos.first;
        }
        posiciones = _filtrarPosiciones();
        hasMore = nuevasTablas.length == perPage;
      });
    } catch (e) {
      debugPrint('❌ Error al cargar tablas: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }
  
  Future<void> _guardarCacheTablas(List<dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _cacheKey();
    final payload = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    };
    prefs.setString(key, jsonEncode(payload));
  }

  Future<void> _loadTablasDesdeCache() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _cacheKey();
    final raw = prefs.getString(key);

    if (raw != null) {
      final decoded = jsonDecode(raw);
      final timestamp = decoded['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;

      if ((now - timestamp) < 3600000) {
        final cached = List<dynamic>.from(decoded['data']);
        setState(() {
          todasLasPosiciones = cached;
          final nuevosTitulos = cached
              .map<String>((tabla) => tabla['titulo']?.toString() ?? 'Sin título')
              .toSet()
              .toList();

          nuevosTitulos.sort((a, b) {
            int prioridad(String titulo) {
              final lower = titulo.toLowerCase();
              if (lower.contains('clausura')) return 0;
              if (lower.contains('apertura')) return 1;
              if (lower.contains('clasificacion')) return 2;
              return 3;
            }

            final p1 = prioridad(a);
            final p2 = prioridad(b);
            return (p1 != p2) ? p1.compareTo(p2) : a.compareTo(b);
          });

          titulosDisponibles = nuevosTitulos;
          if (tituloSeleccionado == null && nuevosTitulos.isNotEmpty) {
            tituloSeleccionado = nuevosTitulos.first;
          }
          posiciones = _filtrarPosiciones();
        });
      }
    }
  }

  String _cacheKey() => 'cache_tablas_${temporadaSeleccionadaId ?? 'todas'}';

  List<dynamic> _filtrarPosiciones() {
    if (tituloSeleccionado == null) return List.from(todasLasPosiciones);
    return todasLasPosiciones.where((tabla) => tabla['titulo'] == tituloSeleccionado).toList();
  }

  Widget _buildTemporadaFilter() {
    final sortedTemporadas = List.from(temporadas)
      ..sort((a, b) => (b['name'] ?? '').compareTo(a['name'] ?? ''));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: sortedTemporadas.map((t) {
          final isSelected = t['name'] == nombreTemporadaSeleccionada;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ElevatedButton(
            onPressed: () {
              setState(() {
                nombreTemporadaSeleccionada = t['name'];
                temporadaSeleccionadaId = t['id'];
              });
              _resetAndFetch();
            },
              style: ElevatedButton.styleFrom(
                backgroundColor: isSelected ? const Color(0xFF00A3FF) : Colors.grey[200],
                foregroundColor: isSelected ? Colors.white : Colors.black87,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: isSelected ? 2 : 0,
              ),
              child: Text(t['name'] ?? 'Temporada'),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTituloFilter() {
    if (titulosDisponibles.isEmpty) return const SizedBox.shrink();
    //final sortedTitulos = List.from(titulosDisponibles)..sort();
    final sortedTitulos = List.from(titulosDisponibles)
      ..sort((a, b) {
        int prioridad(String titulo) {
          final lower = titulo.toLowerCase();
          if (lower.contains('clausura')) return 0;
          if (lower.contains('apertura')) return 1;
          if (lower.contains('clasificacion')) return 2;
          return 3;
        }

        final p1 = prioridad(a);
        final p2 = prioridad(b);

        if (p1 != p2) return p1.compareTo(p2);
        return a.compareTo(b); // orden alfabético si están en la misma prioridad
    });

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: sortedTitulos.map((titulo) {
          final isSelected = titulo == tituloSeleccionado;
          final displayTitle = titulo.split(' ').skip(1).join(' ');
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  tituloSeleccionado = titulo;
                  posiciones = _filtrarPosiciones();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isSelected ? const Color(0xFF00A3FF) : Colors.grey[200],
                foregroundColor: isSelected ? Colors.white : Colors.black87,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: isSelected ? 2 : 0,
              ),
              child: Text(displayTitle),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRow(dynamic tabla, int index) {
    final List<dynamic> equipos = tabla['equipos']
        .where((e) => (e['equipo']?.toString().toLowerCase() ?? '') != 'equipo')
        .toList();

    //Cargar partidos de la temporada seleccionada
    final todosLosPartidos = PartidosCache().partidosJugados;
    final partidosTemporada = todosLosPartidos.where((p) {
      return p['temporada']?.toString() == temporadaSeleccionadaId?.toString();
    }).toList();

    equipos.sort((a, b) {
      final ptsA = _parseInt(a['pts']);
      final ptsB = _parseInt(b['pts']);
      if (ptsB != ptsA) return ptsB.compareTo(ptsA);
      
      final winner = _compararResultadosEntreEquipos(a, b, partidosTemporada);
      if (winner != 0) return -winner;
      
      final dgA = _parseInt(a['dg']);
      final dgB = _parseInt(b['dg']);
      if (dgB != dgA) return dgB.compareTo(dgA);
      
      final gfA = _parseInt(a['gf']);
      final gfB = _parseInt(b['gf']);
      return gfB.compareTo(gfA);
      });
      
    // Tras ordenar, re-asigna posición correlativa
    for (var i = 0; i < equipos.length; i++) {
      equipos[i]['posicion'] = i + 1;
      }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              tabla['titulo'] ?? 'Tabla sin título',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DataTable(
              columnSpacing: 12,
              headingRowHeight: 36,
              dataRowHeight: 48,
              columns: const [
                DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Equipo', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('PTS', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('PJ', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Gol', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('+/-', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('PG', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('PE', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('PP', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: List<DataRow>.generate(equipos.length, (i) {
                final e = equipos[i];
                final String? logoUrl = (e['logo'] is String && e['logo'].toString().isNotEmpty) ? e['logo'] : null;

                return DataRow(
                  color: MaterialStateProperty.resolveWith<Color?>((states) => i.isEven ? Colors.grey[50] : null),
                  cells: [
                    DataCell(Text('${e['posicion']}')),
                    DataCell(Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundImage: logoUrl != null ? NetworkImage(logoUrl) : null,
                          backgroundColor: Colors.grey[300],
                          child: logoUrl == null ? const Icon(Icons.shield, size: 14) : null,
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 100,
                          child: Text(
                            e['equipo'],
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    )),
                    DataCell(Text('${e['pts']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                    DataCell(Text('${e['pj']}')),
                    DataCell(Text('${e['gf']}:${e['gc']}')),
                    DataCell(Text('${e['dg']}')),
                    DataCell(Text('${e['pg']}')),
                    DataCell(Text('${e['pe']}')),
                    DataCell(Text('${e['pp']}')),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('Tablas de posiciones'),
      centerTitle: true,
    ),
    body: Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              _buildTemporadaFilter(),
              if (nombreTemporadaSeleccionada != null) ...[
                const SizedBox(height: 8),
                _buildTituloFilter(),
              ],
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: Colors.white,
            child: posiciones.isEmpty && isLoading
                ? LoadingSeccionConAd(
                    texto: 'Cargando tablas...',
                    adImageUrl: tablaAdUrl,
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: posiciones.length + (hasMore ? 1 : 0),
                    padding: const EdgeInsets.only(top: 8),
                    itemBuilder: (context, index) {
                      if (index < posiciones.length) {
                        return _buildRow(posiciones[index], index);
                      } else {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                    },
                  ),
          ),
        ),
      ],
    ),
    bottomNavigationBar: const ZocaloPublicitario(), // ✅ Insertado aquí
  );
  }
  
  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  int _compararResultadosEntreEquipos(
      dynamic equipoA, dynamic equipoB, List<dynamic> partidosTemporada) {
    final nombreA = equipoA['equipo'];
    final nombreB = equipoB['equipo'];

    for (var partido in partidosTemporada) {
      final local = partido['equipo_local'];
      final visitante = partido['equipo_visitante'];

      if ((local == nombreA && visitante == nombreB) ||
          (local == nombreB && visitante == nombreA)) {
        final golesLocal = _parseInt(partido['goles_local']);
        final golesVisitante = _parseInt(partido['goles_visitante']);

        if (local == nombreA && golesLocal > golesVisitante) return -1;
        if (local == nombreB && golesVisitante > golesLocal) return 1;
        if (local == nombreA && golesVisitante > golesLocal) return 1;
        if (local == nombreB && golesLocal > golesVisitante) return -1;
      }
    }
    return 0;
  }
  Future<List<dynamic>> _obtenerPartidosTemporada() async {
    final todosLosPartidos = PartidosCache().partidosJugados;

    final partidosFiltrados = todosLosPartidos.where((p) {
      return p['temporada']?.toString() == temporadaSeleccionadaId?.toString();
    }).toList();

    if (partidosFiltrados.isNotEmpty) {
      return partidosFiltrados;
    } else {
      // ⚠️ Si no hay partidos en cache, hago el fetch completo
      final res = await ApiService.getPartidos(
        temporada: temporadaSeleccionadaId,
        page: 1,
        perPage: 500,
      );
      final fetched = res['items'] ?? [];

      // Guardar en cache
      //PartidosCache().partidosJugados.addAll(fetched);
      for (final partido in fetched) {
        if (!PartidosCache().partidosJugados.contains(partido)) {
          PartidosCache().partidosJugados.add(partido);
        }
      }
      await CacheService.cachePartidosJugadosPorTemporada(
        temporadaSeleccionadaId!,
        PartidosCache().partidosJugados,
      );

      return fetched;
    }
  }
}

class LoadingSeccionConAd extends StatelessWidget {
  final String texto;
  final String? adImageUrl;

  const LoadingSeccionConAd({super.key, required this.texto, this.adImageUrl});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(texto, style: const TextStyle(fontSize: 14)),
          if (adImageUrl != null && adImageUrl!.isNotEmpty) ...[
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  adImageUrl!,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  width: double.infinity,
                  errorBuilder: (context, error, stackTrace) =>
                      const Text('No se pudo cargar la imagen publicitaria'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}