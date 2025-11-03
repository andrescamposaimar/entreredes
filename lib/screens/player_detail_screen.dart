import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'team_detail_screen.dart';
import 'match_detail_screen.dart';

class Jugador {
  final int id;
  final String nombre;
  final String imagen;
  final String posicion;
  final double puntaje;
  final String caracter;
  final String equipo;
  final int? equipoId;
  final String escudo;
  final String? fechaNacimiento;
  final List<dynamic> temporadas;
  final bool capitan;
  final bool reemplazoAlta;
  final bool reemplazoBaja;

  Jugador({
    required this.id,
    required this.nombre,
    required this.imagen,
    required this.posicion,
    required this.puntaje,
    required this.caracter,
    required this.equipo,
    this.equipoId,
    required this.escudo,
    required this.fechaNacimiento,
    required this.temporadas,
    this.capitan = false,
    this.reemplazoAlta = false,
    this.reemplazoBaja = false,
  });

  factory Jugador.fromJson(Map<String, dynamic> json) {
    final metrics = json['metrics'] ?? {};
    final dynamic puntajeRaw = metrics['puntaje'];
    double parsedPuntaje = 0;

    if (puntajeRaw is num) {
      parsedPuntaje = puntajeRaw.toDouble();
    } else if (puntajeRaw is String) {
      parsedPuntaje = double.tryParse(puntajeRaw.replaceAll(',', '.')) ?? 0;
    }

    return Jugador(
      id: json['id'],
      nombre: json['title']?['rendered'] ?? 'Sin nombre',
      imagen: (json['featured_image'] is String) ? json['featured_image'] : '',
      posicion: (json['posicion'] ?? '-') as String,
      puntaje: parsedPuntaje,
      caracter: metrics['caracter']?.toString() ?? '-',
      equipo: json['equipo']?.toString() ?? 'Sin equipo',
      equipoId: json['equipo_id'] != null ? int.tryParse(json['equipo_id'].toString()) : null,
      escudo: json['escudo'] ?? '',
      fechaNacimiento: json['fecha_nacimiento'],
      temporadas: json['temporadas'] ?? [],
      capitan: json['capitan'] == true,
      reemplazoAlta: json['reemplazo_alta'] == true,
      reemplazoBaja: json['reemplazo_baja'] == true,
    );
  }
}

class PlayerDetailScreen extends StatefulWidget {
  final Map<String, dynamic> player;

  const PlayerDetailScreen({super.key, required this.player});

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  ScrollController? _partidosScrollController;
  late Jugador jugador;

  List<dynamic> temporadas = [];
  List<dynamic> partidos = [];
  bool isLoading = true;
  bool isLoadingMore = false;
  bool hasMore = true;
  int currentPage = 1;
  final int perPage = 16;
  String? error;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _partidosScrollController = ScrollController();
    _partidosScrollController!.addListener(_onScroll);
    jugador = Jugador.fromJson(widget.player);
    _fetchInitialData();
  }

  @override
  void dispose() {
    _partidosScrollController?.removeListener(_onScroll);
    _partidosScrollController?.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_partidosScrollController == null || !_partidosScrollController!.hasClients) return;

    final threshold = 300.0;
    final position = _partidosScrollController!.position;

    if (position.pixels >= position.maxScrollExtent - threshold &&
        !isLoadingMore &&
        hasMore) {
      _fetchMorePartidos();
    }
  }


  Future<void> _fetchInitialData() async {
    if (!mounted) return;
    setState(() => isLoading = true);
    try {
      temporadas = jugador.temporadas;
      final res = await ApiService.getPartidosPorJugador(jugador.id, page: currentPage, perPage: perPage);
      if (!mounted) return;
      final nuevos = res['items'] ?? [];
      final currentPageFromApi = res['current_page'] ?? currentPage;
      final totalPages = res['total_pages'] ?? 1;
      setState(() {
        partidos = nuevos;
        currentPage = currentPageFromApi + 1;
        hasMore = currentPageFromApi < totalPages;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _fetchMorePartidos() async {
    if (!mounted) return;
    setState(() => isLoadingMore = true);
    try {
      final res = await ApiService.getPartidosPorJugador(jugador.id, page: currentPage, perPage: perPage);
      if (!mounted) return;
      final nuevos = res['items'] ?? [];
      final currentPageFromApi = res['current_page'] ?? currentPage;
      final totalPages = res['total_pages'] ?? 1;
      setState(() {
        partidos.addAll(nuevos);
        currentPage = currentPageFromApi + 1;
        hasMore = currentPageFromApi < totalPages;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => isLoadingMore = false);
    }
  }

  String _calculateAge(String? birthDateStr) {
    if (birthDateStr == null || birthDateStr.isEmpty) return "-";
    try {
      final birthDate = DateTime.parse(birthDateStr);
      final today = DateTime.now();
      int age = today.year - birthDate.year;
      if (today.month < birthDate.month || (today.month == birthDate.month && today.day < birthDate.day)) {
        age--;
      }
      return "$age años";
    } catch (_) {
      return "-";
    }
  }

  String _formatFechaNacimiento(String? nacimiento) {
    if (nacimiento != null && nacimiento.isNotEmpty) {
      try {
        final parsed = DateTime.parse(nacimiento);
        return DateFormat('dd/MM/yyyy').format(parsed);
      } catch (_) {
        return '-';
      }
    }
    return '-';
  }

  String _formatearPuntaje(double valor) {
    return valor.truncateToDouble() == valor ? valor.toStringAsFixed(0) : valor.toStringAsFixed(1);
  }

    Widget _teamRow(String nombre, String goles, dynamic escudo) {
    return Row(
      children: [
        if (escudo != null && escudo is String && escudo.isNotEmpty)
          Image.network(escudo, height: 24, width: 24, fit: BoxFit.contain)
        else
          const Icon(Icons.shield, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(child: Text(nombre, style: const TextStyle(fontSize: 16))),
        Text(goles, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildMatchCard(dynamic partido) {
    final liga = partido['liga']?.toString() ?? '';
    final local = partido['equipo_local'] ?? 'Local';
    final visitante = partido['equipo_visitante'] ?? 'Visitante';
    final golesLocal = partido['goles_local']?.toString() ?? '-';
    final golesVisitante = partido['goles_visitante']?.toString() ?? '-';
    final escudoLocal = partido['escudo_local'];
    final escudoVisitante = partido['escudo_visitante'];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(liga, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
            const Divider(height: 20, thickness: 1, color: Color(0xFFE0E0E0)),
            _teamRow(local, golesLocal, escudoLocal),
            const SizedBox(height: 8),
            _teamRow(visitante, golesVisitante, escudoVisitante),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final nombre = jugador.nombre;
    final avatar = jugador.imagen.isNotEmpty ? jugador.imagen : null;
    String posicion = jugador.posicion.isNotEmpty ? jugador.posicion : '-';
    if (jugador.reemplazoAlta) posicion += ' - Reemplazo Alta';
    if (jugador.reemplazoBaja) posicion += ' - Reemplazo Baja';
    final puntaje = _formatearPuntaje(jugador.puntaje);
    final caracter = jugador.caracter;
    final equipo = jugador.equipo;
    final escudo = jugador.escudo;
    final nacimientoFormatted = _formatFechaNacimiento(jugador.fechaNacimiento);
    final edad = _calculateAge(jugador.fechaNacimiento);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(nombre),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: 'Detalles'),
              Tab(text: 'Partidos'),
              Tab(text: 'Temporadas'),
            ],
          ),
        ),
        body: isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Center(
                        child: Stack(
                          alignment: Alignment.topRight,
                          children: [
                            CircleAvatar(
                              radius: 50,
                              backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                              backgroundColor: Colors.grey[300],
                              child: avatar == null ? const Icon(Icons.person, size: 50) : null,
                            ),
                            if (jugador.capitan)
                              Positioned(
                                top: 0,
                                right: 0,
                                child: Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade800,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 3,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Text(
                                      'C',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(nombre, style: Theme.of(context).textTheme.headlineSmall),
                      ),
                      Center(
                        child: (jugador.equipoId != null && equipo != 'Sin equipo')
                            ? GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TeamDetailScreen(
                                        team: {
                                          'id': jugador.equipoId,
                                          'nombre': equipo,
                                          'imagen': escudo,
                                          'leagues': temporadas,
                                          'seasons': temporadas,
                                        },
                                      ),
                                    ),
                                  );
                                },
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (escudo.isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: Image.network(
                                          escudo,
                                          width: 24,
                                          height: 24,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    Text(
                                      equipo,
                                      style: const TextStyle(
                                        color: Colors.cyan,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.chevron_right, size: 18, color: Colors.cyan),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(height: 24),
                      _infoTile('Puntaje', puntaje),
                      _infoTile('Posición', posicion),
                      _infoTile('Fecha de Nacimiento', nacimientoFormatted),
                      _infoTile('Edad', edad),
                      _infoTile('Carácter', caracter),
                    ],
                  ),
                  Builder(
                    builder: (_) {
                      if (isLoading) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      if (partidos.isEmpty) {
                        return const Center(child: Text('No se registran partidos.'));
                      }

                      return ListView.builder(
                        controller: _partidosScrollController!,
                        padding: const EdgeInsets.all(0),
                        itemCount: partidos.length + (isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index < partidos.length) {
                            final p = partidos[index];
                            return _buildMatchCard(p);
                          } else {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                        },
                      );
                    },
                  ),
                  temporadas.isEmpty
                      ? const Center(child: Text('No se registran temporadas.'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: temporadas.length,
                          itemBuilder: (context, index) {
                            final temporada = temporadas[index];
                            return Card(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 2,
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              child: ListTile(
                                leading: const Icon(Icons.calendar_today, color: Colors.cyan),
                                title: Text(temporada.toString()),
                              ),
                            );
                          },
                        ),
                ],
              ),
      ),
    );
  }
}
