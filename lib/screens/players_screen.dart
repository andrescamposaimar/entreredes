import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/cache_service.dart';
import 'player_detail_screen.dart';
import '../services/remote_data_service.dart';
import '../widgets/zocalo_publicitario.dart';

class PlayersScreen extends StatefulWidget {
  const PlayersScreen({super.key});

  @override
  State<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends State<PlayersScreen> {
  List<dynamic> jugadores = [];
  List<dynamic> filteredJugadores = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool isLoading = true;
  bool isLoadingHistorico = false;
  String? adImageUrl;
  int? totalJugadores;
  int totalEsperado = 0;
  int totalCargado = 0;


  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadInitialData() async {
    RemoteDataService.fetchAdImages().then((ads) {
      if (!mounted) return;
      setState(() {
        //adImageUrl = ads['jugadores'];
      });
    });

    final cached = await CacheService.getCachedPlayersTemporada();
    if (cached != null && cached is List && cached.isNotEmpty) {
      jugadores = List.from(cached);
      filteredJugadores = List.from(jugadores);
      totalEsperado = jugadores.length;
      totalCargado = jugadores.length;
      setState(() => isLoading = false);
      return; // 🚫 NO recargar
    }

    try {
      final temporadas = await ApiService.getTemporadas();
      final currentYear = DateTime.now().year.toString();
      final temporadaActual = temporadas.firstWhere(
        (t) => t['name'].toString().contains(currentYear),
        orElse: () => null,
      );

      if (temporadaActual != null && temporadaActual['id'] != null) {
        final response = await ApiService.getJugadoresRaw(
          temporada: temporadaActual['id'],
          page: 1,
          perPage: 7,
        );

        final primeros = response['items'];
        jugadores = List.from(primeros);
        filteredJugadores = List.from(jugadores);
        //totalJugadores = response['total'];
        totalJugadores = response['total'];
        totalCargado = jugadores.length;


        setState(() => isLoading = false);
        _startBackgroundLoading();
      } else {
        final fallback = await ApiService.getJugadores(page: 1, perPage: 7);
        jugadores = List.from(fallback);
        filteredJugadores = List.from(jugadores);
        totalJugadores = jugadores.length;
        setState(() => isLoading = false);
      }
    } catch (e) {
      print('Error al cargar jugadores: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> _startBackgroundLoading() async {
    setState(() => isLoadingHistorico = true);

    int page = 2; // ya cargaste página 1
    const int perPage = 20;
    bool keepLoading = true;
    List<dynamic> historicos = [];

    // 🔄 Estimamos un número alto de jugadores al inicio para que la barra avance suavemente
    totalEsperado = jugadores.length + 800; // estimado más realista al inicio
    totalCargado = jugadores.length;

    while (keepLoading) {
      final nuevos = await ApiService.getJugadores(page: page, perPage: perPage);
      if (nuevos.isEmpty) break;

      final nuevosFiltrados = nuevos.where((n) => !jugadores.any((j) => j['id'] == n['id'])).toList();

      if (nuevosFiltrados.isNotEmpty) {
        historicos.addAll(nuevosFiltrados);
        jugadores.addAll(nuevosFiltrados);
        totalCargado = jugadores.length;
        if (!mounted) return;
        setState(() {});
      }

      if (nuevos.length < perPage) {
        keepLoading = false;
      } else {
        page++;
      }
    }
    
    totalEsperado = jugadores.length;
    totalCargado = jugadores.length;

    if (_searchController.text.trim().isEmpty && mounted) {
      setState(() {
        filteredJugadores = List.from(jugadores);
      });
    }

    if (mounted) setState(() => isLoadingHistorico = false);

    await CacheService.cachePlayersTemporada(jugadores);
  }

  void _filterJugadores(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      final lower = query.toLowerCase();
      setState(() {
        filteredJugadores = jugadores
            .where((j) => (j['title']?['rendered'] ?? '').toLowerCase().contains(lower))
            .toList();
      });
    });
  }

  void _onScroll() {}

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Jugadores')),
      body: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: (totalCargado >= totalEsperado)
                ? Padding(
                    key: const ValueKey('buscador-visible'),
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _filterJugadores,
                      decoration: InputDecoration(
                        hintText: 'Buscar jugador...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('buscador-oculto')),
          ),
          if (isLoadingHistorico && totalEsperado > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      begin: 0,
                      end: (totalCargado / totalEsperado).clamp(0.0, 1.0),
                    ),
                    duration: const Duration(milliseconds: 500),
                    builder: (context, value, _) {
                      return LinearProgressIndicator(
                        value: value,
                        minHeight: 8,
                        backgroundColor: Colors.grey[300],
                        color: Colors.blueAccent,
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Cargando jugadores... ${((totalCargado / totalEsperado) * 100).clamp(0, 100).toStringAsFixed(0)}%',
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                      if (totalCargado >= totalEsperado)
                        const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(
            child: isLoading && jugadores.isEmpty
                ? LoadingSeccionConAd(
                    texto: 'Cargando jugadores...',
                    adImageUrl: adImageUrl,
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: filteredJugadores.length,
                    itemBuilder: (context, index) {
                      try {
                        final j = filteredJugadores[index];

                        // 🔹 Validación de nombre
                        final rawTitle = j['title'];
                        final nombre = (rawTitle is Map && rawTitle['rendered'] is String && rawTitle['rendered'].toString().isNotEmpty)
                            ? rawTitle['rendered']
                            : 'Sin nombre';

                        // 🔹 Validación de edad
                        final edad = _calcularEdad(j['fecha_nacimiento']);

                        // 🔹 Validación segura de imagen
                        final rawFoto = j['featured_image'];
                        final foto = (rawFoto is String && rawFoto.isNotEmpty) ? rawFoto : null;

                        // 🔹 Puntaje robusto
                        final puntaje = _formatearPuntaje(j['metrics']?['puntaje']);

                        // 🔹 Posición segura y color
                        final rawPos = (j['posicion'] ?? '').toString();
                        final posicion = rawPos.isEmpty || rawPos.toLowerCase() == 'sin posicion'
                            ? 'Sin Cargar'
                            : rawPos.toLowerCase() == 'mediocampista' ? 'Medio.' : rawPos;

                        Color bgColor;
                        switch (posicion.toLowerCase()) {
                          case 'arquero':
                            bgColor = Colors.cyan.shade700;
                            break;
                          case 'defensor':
                            bgColor = Colors.indigo.shade600;
                            break;
                          case 'medio.':
                            bgColor = Colors.orange.shade600;
                            break;
                          case 'delantero':
                            bgColor = Colors.red.shade600;
                            break;
                          case 'sin cargar':
                            bgColor = Colors.grey.shade600;
                            break;
                          default:
                            bgColor = Colors.grey.shade400;
                        }

                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          child: Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    )
                                  ],
                                ),
                                child: ListTile(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => PlayerDetailScreen(player: j),
                                      ),
                                    );
                                  },
                                  contentPadding: const EdgeInsets.only(left: 36, right: 16, top: 12, bottom: 12),
                                  leading: foto != null
                                      ? CircleAvatar(backgroundImage: NetworkImage(foto))
                                      : const Icon(Icons.person, size: 40),
                                  title: Text(nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  subtitle: Text('Edad: $edad', style: const TextStyle(fontSize: 13)),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Text('Pts.', style: TextStyle(fontSize: 11)),
                                      Text(
                                        puntaje,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                top: 10,
                                bottom: 10,
                                child: FractionallySizedBox(
                                  heightFactor: 0.9,
                                  child: Container(
                                    width: 28,
                                    decoration: BoxDecoration(
                                      color: bgColor,
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(6),
                                        bottomRight: Radius.circular(6),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 6,
                                          offset: const Offset(2, 2),
                                        )
                                      ],
                                    ),
                                    child: Center(
                                      child: RotatedBox(
                                        quarterTurns: -1,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                                          child: Text(
                                            posicion,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      } catch (e, stack) {
                        print('🛑 Error al renderizar jugador en index $index: $e\n$stack');
                        return const ListTile(
                          title: Text('Error al mostrar jugador'),
                          subtitle: Text('Este jugador tiene datos inválidos.'),
                        );
                      }
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: const ZocaloPublicitario(),
    );
  }

  int _calcularEdad(dynamic fechaNacimiento) {
    if (fechaNacimiento is! String || fechaNacimiento.isEmpty) return 0;
    try {
      final nacimiento = DateTime.parse(fechaNacimiento);
      final hoy = DateTime.now();
      int edad = hoy.year - nacimiento.year;
      if (hoy.month < nacimiento.month || (hoy.month == nacimiento.month && hoy.day < nacimiento.day)) {
        edad--;
      }
      return edad;
    } catch (_) {
      return 0;
    }
  }

  String _formatearPuntaje(dynamic valor) {
    try {
      if (valor == null || valor is bool) return '-';
      if (valor is num) {
        return valor.toStringAsFixed(valor.truncateToDouble() == valor ? 0 : 1);
      }
      if (valor is String) {
        final normalizado = valor.replaceAll(',', '.');
        final numParsed = double.tryParse(normalizado);
        if (numParsed != null) {
          return numParsed.toStringAsFixed(numParsed.truncateToDouble() == numParsed ? 0 : 1);
        }
      }
    } catch (_) {}
    return '-';
  }
}

class LoadingSeccionConAd extends StatelessWidget {
  final String texto;
  final String? adImageUrl;

  const LoadingSeccionConAd({
    super.key,
    required this.texto,
    this.adImageUrl,
  });

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
          ]
        ],
      ),
    );
  }
}