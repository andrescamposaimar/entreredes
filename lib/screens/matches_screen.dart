import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'match_detail_screen.dart';
import '../widgets/zocalo_publicitario.dart';
import 'dart:async';
import '../services/remote_data_service.dart';
import '../services/partidos_cache.dart';
import '../services/cache_service.dart';



const int temporadaActualId = 196; // Cambiar según corresponda

class MatchesScreen extends StatefulWidget {
  final int temporadaId;
  const MatchesScreen({super.key, required this.temporadaId});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  String selectedFilterJugados = 'fecha'; // 'fecha', 'zona' o 'equipo'
  int? selectedEquipoId;
  String? selectedEquipoNombre;
  String? selectedEquipoEscudo;
  List<dynamic> equiposTemporada = [];
  bool isCargandoEquipos = false;
  Timer? _liveTimer;
  bool _showLiveDot = true;
  Timer? _blinkingTimer;

  DateTime? _simulatedStartTime;

  final ScrollController _scrollControllerJugados = ScrollController();
  final ScrollController _scrollControllerFuturos = ScrollController();

  List<dynamic> partidosJugados = [];
  List<dynamic> partidosFuturos = [];

  int currentPageJugados = 1;
  int currentPageFuturos = 1;

  bool isLoadingMoreJugados = false;
  bool isLoadingMoreFuturos = false;

  bool isInitialLoadingJugados = true;
  bool isInitialLoadingFuturos = true;

  bool hasMoreJugados = true;
  bool hasMoreFuturos = true;

  String? error;

  int selectedTab = 0;

  List<dynamic> partidosPorEquipo = [];
  bool isLoadingPorEquipo = false;

  List<dynamic> get _partidosLive {
    final now = DateTime.now();

    return partidosFuturos.where((p) {
      final fecha = p['fecha'] ?? '';
      final hora = p['hora'] ?? '00:00';
      final fechaHora = DateTime.tryParse('$fecha $hora');
      final status = p['status'] ?? 'publish';

      return status == 'future' &&
          fechaHora != null &&
          fechaHora.year == now.year &&
          fechaHora.month == now.month &&
          fechaHora.day == now.day &&
          fechaHora.isBefore(now) &&
          now.difference(fechaHora).inMinutes < 60;
    }).toList();
  }


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadCachedThenFetchJugados();
    _loadCachedThenFetchFuturos();

    _scrollControllerJugados.addListener(() {
      if (_scrollControllerJugados.position.pixels >= _scrollControllerJugados.position.maxScrollExtent - 200 &&
          !isLoadingMoreJugados && hasMoreJugados) {
        _fetchPartidosJugados();
      }
    });

    _scrollControllerFuturos.addListener(() {
      if (_scrollControllerFuturos.position.pixels >= _scrollControllerFuturos.position.maxScrollExtent - 200 &&
          !isLoadingMoreFuturos && hasMoreFuturos) {
        _fetchPartidosFuturos();
      }
    });

    _tabController.addListener(() {
      if (mounted) {
        setState(() {
          selectedTab = _tabController.index;
        });
      }
    });

    _liveTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    _blinkingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _showLiveDot = !_showLiveDot;
        });
      }
    });
  }

  Widget _buildListaJugadosFiltrada() {
    if (isInitialLoadingJugados) return const Center(child: CircularProgressIndicator());

    if (selectedFilterJugados == 'fecha') return _buildListaPorFecha();
    if (selectedFilterJugados == 'zona') return _buildListaPorZona();
    if (selectedFilterJugados == 'equipo') return _buildListaPorEquipo();

    return const SizedBox.shrink();
  }

  Widget _buildListaProximosPartidos() {
    if (isInitialLoadingFuturos) return const Center(child: CircularProgressIndicator());
    if (partidosFuturos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_busy, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Próxima Fecha aún no ha sido cargada por la comisión de fútbol',
                style: const TextStyle(fontSize: 16, color: Colors.black54),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      controller: _scrollControllerFuturos,
      itemCount: partidosFuturos.length,
      itemBuilder: (context, index) => _buildMatchCard(partidosFuturos[index]),
    );
  }

  @override
  void dispose() {
    _scrollControllerJugados.dispose();
    _scrollControllerFuturos.dispose();
    _tabController.dispose();
    _liveTimer?.cancel();
    _blinkingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCachedThenFetchJugados() async {
    final cached = await _loadCache('jugados');
    if (cached != null) {
      setState(() {
        partidosJugados = cached;
        currentPageJugados = 2;
        isInitialLoadingJugados = false;
      });
      _fetchPartidosJugados();
    } else {
      await _fetchPartidosJugados(initial: true);
    }
  }

  Future<void> _loadCachedThenFetchFuturos() async {
    final cached = await _loadCache('futuros');
    if (cached != null) {
      setState(() {
        partidosFuturos = cached;
        currentPageFuturos = 2;
        isInitialLoadingFuturos = false;
      });
      _fetchPartidosFuturos();
    } else {
      await _fetchPartidosFuturos(initial: true);
    }
  }

  Future<void> _fetchPartidosJugados({bool initial = false}) async {
    if (initial && mounted) setState(() => isInitialLoadingJugados = true);
    if (mounted) setState(() => isLoadingMoreJugados = true);

    try {
      final res = await ApiService.getPartidos(page: currentPageJugados);
      final nuevos = res['items'] ?? [];

      if (currentPageJugados == 1 && nuevos.isNotEmpty) {
        await _guardarCache('jugados', nuevos);
      }

      if (!mounted) return;

      setState(() {
        if (initial) {
          partidosJugados = nuevos;
          currentPageJugados = 2;
        } else {
          partidosJugados.addAll(nuevos);
          currentPageJugados++;
        }
        hasMoreJugados = nuevos.length >= 16;
      });
      // Guardar en memoria (singleton)
      PartidosCache().partidosJugados = partidosJugados;

      // Guardar en caché persistente por temporada
      await CacheService.cachePartidosJugadosPorTemporada(
        widget.temporadaId,
        partidosJugados,
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          isLoadingMoreJugados = false;
          isInitialLoadingJugados = false;
        });
      }
    }
  }

  Future<void> _fetchPartidosFuturos({bool initial = false}) async {
    if (initial && mounted) setState(() => isInitialLoadingFuturos = true);
    if (mounted) setState(() => isLoadingMoreFuturos = true);

    try {
      final res = await ApiService.getPartidosProgramados(page: currentPageFuturos);
      final nuevos = res['items'] ?? [];

      nuevos.sort((a, b) {
        final fechaHoraA = DateTime.tryParse('${a['fecha'] ?? ''} ${a['hora'] ?? '00:00'}') ?? DateTime(2100);
        final fechaHoraB = DateTime.tryParse('${b['fecha'] ?? ''} ${b['hora'] ?? '00:00'}') ?? DateTime(2100);
        return fechaHoraA.compareTo(fechaHoraB);
      });

      if (currentPageFuturos == 1 && nuevos.isNotEmpty) {
        await _guardarCache('futuros', nuevos);
      }

      if (!mounted) return;

      setState(() {
        if (initial) {
          partidosFuturos = nuevos;
          currentPageFuturos = 2;
        } else {
          partidosFuturos.addAll(nuevos);
          currentPageFuturos++;
        }

        partidosFuturos.sort((a, b) {
          final fechaHoraA = DateTime.tryParse('${a['fecha'] ?? ''} ${a['hora'] ?? '00:00'}') ?? DateTime(2100);
          final fechaHoraB = DateTime.tryParse('${b['fecha'] ?? ''} ${b['hora'] ?? '00:00'}') ?? DateTime(2100);
          return fechaHoraA.compareTo(fechaHoraB);
        });

        hasMoreFuturos = nuevos.length >= 16;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          isLoadingMoreFuturos = false;
          isInitialLoadingFuturos = false;
        });
      }
    }
  }

  Future<void> _guardarCache(String key, List<dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    };
    prefs.setString('cache_partidos_$key', jsonEncode(payload));
  }

  Future<List<dynamic>?> _loadCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cache_partidos_$key');
    if (raw != null) {
      final decoded = jsonDecode(raw);
      final timestamp = decoded['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;
      if ((now - timestamp) < 3600000) {
        return List<dynamic>.from(decoded['data']);
      }
    }
    return null;
  }
  Widget _buildLiveMatchCard(dynamic partido) {
    final now = DateTime.now();
    final inicio = DateTime.tryParse('${partido['fecha']} ${partido['hora'] ?? '00:00'}') ?? now;
    final duration = now.difference(inicio);
    final minutos = duration.inMinutes;
    final bool terminado = minutos >= 60;
    final liga = _decodeHtmlEntities(partido['liga']?.toString());
    final cancha = _decodeHtmlEntities(partido['cancha'] ?? '');
    final hora = partido['hora'] ?? '';
    final local = _decodeHtmlEntities(partido['equipo_local'] ?? '');
    final visitante = _decodeHtmlEntities(partido['equipo_visitante'] ?? '');
    final escudoLocal = partido['escudo_local'];
    final escudoVisitante = partido['escudo_visitante'];
    final golesLocal = _parseGoles(partido['goles_local']) != '-' ? _parseGoles(partido['goles_local']) : '0';
    final golesVisitante = _parseGoles(partido['goles_visitante']) != '-' ? _parseGoles(partido['goles_visitante']) : '0';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(liga, style: const TextStyle(fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    if (!terminado && _showLiveDot)
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red,
                        ),
                      ),
                    Text(
                      terminado ? 'Finalizado' : '$minutos\'',
                      style: TextStyle(
                        fontSize: 18,
                        color: terminado ? Colors.grey : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: _teamRow(local, escudoLocal, golesLocal)),
                const SizedBox(width: 6),
                Expanded(child: _teamRow(visitante, escudoVisitante, golesVisitante)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Icon(Icons.location_on, size: 16, color: Colors.green),
                const SizedBox(width: 4),
                Flexible(child: Text(cancha, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 12),
                const Icon(Icons.access_time, size: 16, color: Colors.green),
                const SizedBox(width: 4),
                Text(hora),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListaPartidosLive() {
    final live = _partidosLive;
    if (live.isEmpty) {
      return const Center(child: Text('No hay partidos en vivo.'));
    }
    return ListView.builder(
      itemCount: live.length,
      itemBuilder: (_, i) => _buildLiveMatchCard(live[i]),
    );
  }

  Widget _buildMatchCard(dynamic partido) {
    final liga = _decodeHtmlEntities(partido['liga']?.toString());
    final local = _decodeHtmlEntities(partido['equipo_local']?.toString());
    final visitante = _decodeHtmlEntities(partido['equipo_visitante']?.toString());
    final escudoLocal = partido['escudo_local']?.toString();
    final escudoVisitante = partido['escudo_visitante']?.toString();
    final fecha = partido['fecha'] ?? '-';
    final hora = partido['hora'] ?? '-';
    final cancha = _decodeHtmlEntities(partido['cancha']?.toString() ?? '-');

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(liga, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
            const Divider(height: 16, thickness: 1, color: Color(0xFFE0E0E0)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      _teamRow(local, escudoLocal, selectedTab == 0 ? _parseGoles(partido['goles_local']) : ''),
                      const SizedBox(height: 6),
                      _teamRow(visitante, escudoVisitante, selectedTab == 0 ? _parseGoles(partido['goles_visitante']) : ''),
                    ],
                  ),
                ),
                if (selectedTab == 1)
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: Colors.green),
                            const SizedBox(width: 4),
                            Text(_formatearFecha(fecha), style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time, size: 16, color: Colors.green),
                            const SizedBox(width: 4),
                            Text(hora, style: const TextStyle(fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.location_on, size: 16, color: Colors.green),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                cancha.isNotEmpty ? cancha : '-',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (selectedTab == 0)
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MatchDetailScreen(partido: partido),
                        ),
                      );
                    },
                    child: const Text('Ver detalle'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _teamRow(String nombre, String? escudoUrl, String goles) {
    return Row(
      children: [
        if (escudoUrl != null && escudoUrl.isNotEmpty && Uri.tryParse(escudoUrl)?.hasScheme == true)
          Image.network(
            escudoUrl,
            width: 24,
            height: 24,
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.shield, size: 20, color: Colors.grey),
          )
        else
          const Icon(Icons.shield, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(child: Text(nombre, style: const TextStyle(fontSize: 16))),
        Text(goles, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Partidos'),
        centerTitle: true,
        actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar caché de partidos',
              onPressed: _mostrarDialogYActualizarCache,
            ),
          ],
      ),
      body: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Theme.of(context).primaryColor,
              tabs: const [
                Tab(text: 'Jugados'),
                Tab(text: 'Prox. Fecha'),
                Tab(text: 'Live'),
              ],
            ),
          ),
          if (selectedTab == 0) _filtroJugadosSelector(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildListaJugadosFiltrada(),
                _buildListaProximosPartidos(),
                _buildListaPartidosLive(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ZocaloPublicitario(),
        ],
      ),
    );
  }

  Widget _filtroJugadosSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _filtroButton('fecha', 'Por Fecha'),
          _filtroButton('zona', 'Por Zona'),
          _filtroButton('equipo', 'Por Equipo'),
        ],
      ),
    );
  }

  Widget _filtroButton(String value, String label) {
    final bool selected = selectedFilterJugados == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          selectedFilterJugados = value;
          if (value != 'equipo') {
            selectedEquipoId = null;
            selectedEquipoNombre = null;
            selectedEquipoEscudo = null;
          } else if (equiposTemporada.isEmpty && !isCargandoEquipos) {
            _cargarEquiposTemporadaActual();
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF00A3FF) : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
  String _formatearFecha(String fechaOriginal) {
    try {
      final partes = fechaOriginal.split('-');
      if (partes.length == 3) {
        final yyyy = partes[0];
        final mm = partes[1];
        final dd = partes[2];
        final yy = yyyy.substring(2);
        return '$dd-$mm-$yy';
      }
    } catch (_) {}
    return fechaOriginal;
  }

  String _decodeHtmlEntities(String? text) {
    if (text == null || text.isEmpty) return '-';
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&#8211;', '-')
        .replaceAll('&quot;', '"')
        .replaceAll('&#8217;', "'")
        .replaceAll('&#038;', '&')
        .replaceAll('&#8216;', "'");
  }

  String _parseGoles(dynamic valor) {
    if (valor == null || valor.toString().trim().isEmpty) return '-';
    return valor.toString();
  }

Widget _buildListaPorFecha() {
  final Map<String, List<dynamic>> grupos = {};
  for (var partido in partidosJugados) {
    final fecha = partido['fecha']?.toString() ?? 'Sin fecha';
    grupos.putIfAbsent(fecha, () => []).add(partido);
  }

  final fechasOrdenadas = grupos.keys.toList()
    ..sort((a, b) => b.compareTo(a)); // DESCENDENTE

    int prioridadLiga(String? liga) {
      final l = liga?.toLowerCase() ?? '';

      // Detectar patrones como: "apertura ... a", "clausura ... c"
      final aperturaMatch = RegExp(r'apertura.*\b(a|b|c)\b').firstMatch(l);
      final clausuraMatch = RegExp(r'clausura.*\b(a|b|c)\b').firstMatch(l);

      if (clausuraMatch != null) {
        switch (clausuraMatch.group(1)) {
          case 'a': return 0;
          case 'b': return 1;
          case 'c': return 2;
        }
      }

      if (aperturaMatch != null) {
        switch (aperturaMatch.group(1)) {
          case 'a': return 3;
          case 'b': return 4;
          case 'c': return 5;
        }
      }

      if (l.contains('clasificacion')) return 6;

      return 7;
    }

  final children = fechasOrdenadas.expand((fecha) {
    final partidos = grupos[fecha]!
      ..sort((a, b) {
        final pa = prioridadLiga(a['liga']?.toString());
        final pb = prioridadLiga(b['liga']?.toString());
        return pa.compareTo(pb);
      });

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
        child: Text(fecha, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      ...partidos.map((p) => _buildMatchCard(p)).toList(),
    ];
  }).toList();

  if (isLoadingMoreJugados) {
    children.add(
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: Text('Cargando más partidos...')),
      ),
    );
  }

  return ListView(
    controller: _scrollControllerJugados,
    children: children,
  );
}

  Widget _buildListaPorZona() {
    final Map<String, List<dynamic>> grupos = {};
    final partidosOrdenados = [...partidosJugados]..sort((a, b) => (b['id'] ?? 0).compareTo(a['id'] ?? 0));

    for (var partido in partidosOrdenados) {
      final liga = partido['liga']?.toString() ?? 'Sin liga';
      grupos.putIfAbsent(liga, () => []).add(partido);
    }

    final entradasOrdenadas = grupos.entries.toList()
      ..sort((a, b) => prioridadEncabezadoLiga(a.key).compareTo(prioridadEncabezadoLiga(b.key)));

    final children = entradasOrdenadas.expand((entry) {
      final liga = entry.key;
      final partidos = entry.value;
      return [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 4),
          child: Text(liga, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        ...partidos.map((p) => _buildMatchCard(p)).toList(),
      ];
    }).toList();

    if (isLoadingMoreJugados) {
      children.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(child: Text('Cargando más partidos...')),
        ),
      );
    }

    return ListView(
      controller: _scrollControllerJugados,
      children: children,
    );
  }

  int prioridadEncabezadoLiga(String? liga) {
  final l = liga?.toLowerCase() ?? '';

  final clausuraMatch = RegExp(r'clausura.*\b(a|b|c)\b').firstMatch(l);
  if (clausuraMatch != null) {
    switch (clausuraMatch.group(1)) {
      case 'a': return 0;
      case 'b': return 1;
      case 'c': return 2;
    }
  }

  final aperturaMatch = RegExp(r'apertura.*\b(a|b|c)\b').firstMatch(l);
    if (aperturaMatch != null) {
      switch (aperturaMatch.group(1)) {
        case 'a': return 3;
        case 'b': return 4;
        case 'c': return 5;
      }
    }

    final clasifMatch = RegExp(r'clasificacion.*\b([1-6])\b').firstMatch(l);
    if (clasifMatch != null) {
      return 6 + int.parse(clasifMatch.group(1)!); // 7–12
    }

    return 99; // cualquier otra liga
  }

  Widget _buildListaPorEquipo() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[300],
                  image: selectedEquipoEscudo != null
                      ? DecorationImage(image: NetworkImage(selectedEquipoEscudo!), fit: BoxFit.cover)
                      : null,
                ),
                child: selectedEquipoEscudo == null
                    ? const Icon(Icons.shield, color: Colors.grey)
                    : null,
              ),
              Expanded(
                child: isCargandoEquipos
                    ? const Center(child: CircularProgressIndicator())
                    : DropdownButtonHideUnderline(
                        child: Container(
                          height: 48,
                          alignment: Alignment.center,
                          child: DropdownButton<int>(
                            isExpanded: true,
                            isDense: true,
                            value: selectedEquipoId,
                            hint: const Text('Seleccionar equipo'),
                            selectedItemBuilder: (context) {
                              return equiposTemporada.map<Widget>((equipo) {
                                final rawName = equipo['nombre'];
                                final name = (rawName is String) ? rawName : '';
                                return Text(name);
                              }).toList();
                            },
                            items: equiposTemporada.map<DropdownMenuItem<int>>((equipo) {
                              final rawLogo = equipo['escudo'] ?? equipo['imagen'];
                              final logo = (rawLogo is String && rawLogo.isNotEmpty) ? rawLogo : null;
                              final rawName = equipo['nombre'];
                              final name = (rawName is String) ? rawName : '';
                              return DropdownMenuItem<int>(
                                value: equipo['id'],
                                child: Row(
                                  children: [
                                    if (logo != null)
                                      Image.network(
                                        logo,
                                        width: 24,
                                        height: 24,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.shield, size: 20),
                                      )
                                    else
                                      const Icon(Icons.shield, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(name)),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (int? newId) async {
                              final equipo = equiposTemporada.firstWhere((e) => e['id'] == newId);
                              setState(() {
                                selectedEquipoId = newId;
                                final rawName = equipo['nombre'];
                                selectedEquipoNombre = (rawName is String) ? rawName : '';
                                final rawEscudo = equipo['escudo'];
                                final rawImagen = equipo['imagen'];
                                selectedEquipoEscudo = (rawEscudo is String && rawEscudo.isNotEmpty)
                                    ? rawEscudo
                                    : (rawImagen is String && rawImagen.isNotEmpty)
                                        ? rawImagen
                                        : null;
                                isLoadingPorEquipo = true;
                                partidosPorEquipo = [];
                              });
                              try {
                                final partidos = await ApiService.getHistorialDePartidosPorEquipo(selectedEquipoNombre ?? '');
                                setState(() {
                                  partidosPorEquipo = partidos;
                                  isLoadingPorEquipo = false;
                                });
                              } catch (e) {
                                setState(() {
                                  partidosPorEquipo = [];
                                  isLoadingPorEquipo = false;
                                });
                              }
                            },
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
        const Divider(),
        if (selectedEquipoId == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Seleccioná un equipo para ver sus partidos',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else if (isLoadingPorEquipo)
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Expanded(
            child: Builder(
              builder: (context) {
                final partidosFiltrados = partidosPorEquipo
                  ..sort((a, b) => b['fecha'].compareTo(a['fecha']));
                return ListView(
                  controller: _scrollControllerJugados,
                  children: partidosFiltrados.map<Widget>((p) => _buildMatchCard(p)).toList(),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _cargarEquiposTemporadaActual() async {
    setState(() => isCargandoEquipos = true);
    try {
      final cached = await _cargarCacheEquipos();
      if (cached != null) {
        final listas = await RemoteDataService.fetchListasJugadores();
        final idsAExcluir = [
          ...?listas['espera'],
          ...?listas['reserva'],
          ...?listas['no_inscriptos'],
        ];

        final filtrados = cached
            .where((e) => !idsAExcluir.contains(e['id']))
            .toList()
          ..sort((a, b) => (a['nombre'] ?? '').toString().toLowerCase().compareTo((b['nombre'] ?? '').toString().toLowerCase()));

        setState(() {
          equiposTemporada = filtrados;
          isCargandoEquipos = false;
        });
        return;
      }

      final listas = await RemoteDataService.fetchListasJugadores();
      final idsAExcluir = [
        ...?listas['espera'],
        ...?listas['reserva'],
        ...?listas['no_inscriptos'],
      ];

      final res = await ApiService.getEquipos(temporada: widget.temporadaId);
      final filtrados = res
          .where((e) => !idsAExcluir.contains(e['id']))
          .toList()
        ..sort((a, b) => (a['nombre'] ?? '').toString().toLowerCase().compareTo((b['nombre'] ?? '').toString().toLowerCase()));

      setState(() {
        equiposTemporada = filtrados;
      });
      await _guardarCacheEquipos(filtrados);
    } catch (e) {
      debugPrint('Error cargando equipos: $e');
    } finally {
      setState(() => isCargandoEquipos = false);
    }
  }

  Future<void> _guardarCacheEquipos(List<dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    };
    prefs.setString('cache_equipos_${widget.temporadaId}', jsonEncode(payload));
  }

  Future<List<dynamic>?> _cargarCacheEquipos() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('cache_equipos_${widget.temporadaId}');
    if (raw != null) {
      final decoded = jsonDecode(raw);
      final timestamp = decoded['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;
      const sieteDiasEnMs = 7 * 24 * 60 * 60 * 1000;
      if ((now - timestamp) < sieteDiasEnMs) {
        return List<dynamic>.from(decoded['data']);
      }
    }
    return null;
  }

  Future<void> _mostrarDialogYActualizarCache() async {
    showDialog(
      context: context,
      barrierDismissible: false, // 🔒 impide tocar fuera del modal
      builder: (BuildContext context) {
        return AlertDialog(
          content: Row(
            children: const [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(child: Text('Actualizando cache de partidos...')),
            ],
          ),
        );
      },
    );

    await _forzarActualizacionCacheJugados(); // Llama a la función original

    if (mounted) {
      Navigator.of(context).pop(); // Cierra el modal
    }
  }

  Future<void> _forzarActualizacionCacheJugados() async {
    try {
      final res = await ApiService.getPartidos(page: 1, perPage: 32);
      final nuevos = res['items'] ?? [];

      if (nuevos.isNotEmpty) {
        await _guardarCache('jugados', nuevos);
        if (mounted) {
          setState(() {
            partidosJugados = nuevos;
            currentPageJugados = 2;
            hasMoreJugados = nuevos.length >= 16;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Caché actualizada correctamente')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al actualizar caché: $e')),
        );
      }
    }
  }
}
