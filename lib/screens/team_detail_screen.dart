import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'match_detail_screen.dart';
import 'player_detail_screen.dart';
import '../services/cache_service.dart';
import '../widgets/zocalo_publicitario.dart';


class Jugador {
  final int id;
  final String nombre;
  final String puntaje;
  final String? imagen;
  final String posicion;
  final bool capitan;
  final bool reemplazoAlta;
  final bool reemplazoBaja;
  final Map<String, dynamic> raw;

  Jugador({
    required this.id,
    required this.nombre,
    required this.puntaje,
    this.imagen,
    required this.posicion,
    required this.capitan,
    required this.reemplazoAlta,
    required this.reemplazoBaja,
    required this.raw,
  });

  factory Jugador.fromJson(Map<String, dynamic> json) {
    final imagenRaw = json['featured_image'];
    return Jugador(
      id: json['id'],
      nombre: json['title']?['rendered'] ?? 'Sin nombre',
      puntaje: json['metrics']?['puntaje']?.toString() ?? '-',
      imagen: (imagenRaw is String && imagenRaw.isNotEmpty) ? imagenRaw : null,
      posicion: (json['posicion'] ?? json['position'] ?? '–').toString(),
      capitan: json['capitan'] == true,
      reemplazoAlta: json['reemplazo_alta'] == true,
      reemplazoBaja: json['reemplazo_baja'] == true,
      raw: json,
    );
  }

  Map<String, dynamic> toJson() => raw;
}

class TeamDetailScreen extends StatefulWidget {
  final Map<String, dynamic> team;
  const TeamDetailScreen({super.key, required this.team});

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> with SingleTickerProviderStateMixin {
  List<dynamic> partidos = [];
  List<Jugador> jugadores = [];
  bool isLoadingPartidos = false;
  bool isLoadingJugadores = false;
  String? errorPartidos;
  String? errorJugadores;
  late TabController _tabController;

@override
void initState() {
  super.initState();
  _tabController = TabController(length: 2, vsync: this);
  _loadJugadoresDesdeCache();
  _fetchPartidos();
  _fetchJugadores();
}

  Future<void> _loadJugadoresDesdeCache() async {
    final cached = await CacheService.getCachedPlayersPorEquipo(widget.team['id']);
    if (cached != null && mounted) {
      final ordenPosiciones = {'Arquero': 1, 'Defensor': 2, 'Mediocampista': 3, 'Delantero': 4};
      final lista = cached.map<Jugador>((j) => Jugador.fromJson(j)).toList();
      lista.sort((a, b) => (ordenPosiciones[a.posicion] ?? 99).compareTo(ordenPosiciones[b.posicion] ?? 99));
      setState(() => jugadores = lista);
    }
  }

  Future<void> _fetchPartidos() async {
    setState(() => isLoadingPartidos = true);
    try {
      final teamId = widget.team['id'];
      final nuevos = await ApiService.getPartidosPorEquipoId(teamId);
      nuevos.sort((a, b) => (b['id'] ?? 0).compareTo(a['id'] ?? 0));
      if (!mounted) return;
      setState(() => partidos = nuevos);
    } catch (e) {
      if (!mounted) return;
      setState(() => errorPartidos = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => isLoadingPartidos = false);
    }
  }

  Future<void> _fetchJugadores() async {
    if (!mounted) return;
    setState(() => isLoadingJugadores = true);
    try {
      final teamId = widget.team['id'];
      final res = await ApiService.getJugadoresRaw(equipoId: teamId);
      final nuevos = res['items'] ?? [];

      if (!mounted) return;

      final ordenPosiciones = {'Arquero': 1, 'Defensor': 2, 'Mediocampista': 3, 'Delantero': 4};

      // 🔥 Filtrá solo jugadores con el equipo_id coincidente (convertido a int)
      /*final jugadoresFiltrados = nuevos.where((j) {
        final equipoId = j['equipo_id'];
        if (equipoId == null) return false;
        return equipoId.toString() == teamId.toString();
      }).toList();*/
      final jugadoresFiltrados = nuevos;
      // final lista = jugadoresFiltrados.map<Jugador>((j) => Jugador.fromJson(j)).toList();

      final lista = <Jugador>[];
        for (var j in jugadoresFiltrados) {
          try {
            lista.add(Jugador.fromJson(j));
          } catch (e) {
            debugPrint('Jugador descartado por error de parseo (ID: ${j['id']}): $e');
          }
      }

      lista.sort((a, b) =>
          (ordenPosiciones[a.posicion] ?? 99).compareTo(ordenPosiciones[b.posicion] ?? 99));

      setState(() => jugadores = lista);
    } catch (e) {
      if (!mounted) return;
      setState(() => errorJugadores = e.toString());
    } finally {
      if (!mounted) return;
      setState(() => isLoadingJugadores = false);
    }
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

  Widget _buildPlayerCard(Jugador jugador) {
    final edad = _calcularEdad(jugador.raw['fecha_nacimiento']);

    final rawPos = jugador.posicion.toLowerCase();
    final posicion = rawPos.isEmpty || rawPos == 'sin posicion'
        ? 'Sin Cargar'
        : rawPos == 'mediocampista' ? 'Medio.' : jugador.posicion;

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
                    builder: (_) => PlayerDetailScreen(player: jugador.toJson()),
                  ),
                );
              },
              contentPadding: const EdgeInsets.only(left: 36, right: 16, top: 12, bottom: 12),
              leading: jugador.imagen != null
                  ? CircleAvatar(backgroundImage: NetworkImage(jugador.imagen!))
                  : const Icon(Icons.person, size: 40),
              title: Text(jugador.nombre, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Row(
                children: [
                  Text('Edad: $edad', style: const TextStyle(fontSize: 13)),
                  if (jugador.reemplazoAlta)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.arrow_upward, size: 16, color: Colors.green),
                    ),
                  if (jugador.reemplazoBaja)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.arrow_downward, size: 16, color: Colors.red),
                    ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Pts.', style: TextStyle(fontSize: 11)),
                  Text(
                    jugador.puntaje,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
  @override
  Widget build(BuildContext context) {
    final team = widget.team;
    final nombre = team['nombre']?.toString() ?? 'Sin nombre';
    final avatarUrl = team['imagen'] is String ? team['imagen'] : null;

    final activos = jugadores.where((j) => !j.reemplazoBaja).toList();
    final bajas = jugadores.where((j) => j.reemplazoBaja).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              if (avatarUrl != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Image.network(
                    avatarUrl,
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                ),
              Expanded(
                child: Text(
                  nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          centerTitle: true,
        ),
        body: Column(
          children: [
            const SizedBox(height: 12),
            TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Theme.of(context).primaryColor,
              tabs: const [
                Tab(text: 'Plantel'),
                Tab(text: 'Partidos'),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Plantel
                  errorJugadores != null
                      ? Center(child: Text('Error al cargar jugadores: \$errorJugadores'))
                      : isLoadingJugadores
                          ? const Center(child: CircularProgressIndicator())
                          : jugadores.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.person_off, size: 48, color: Colors.grey),
                                      SizedBox(height: 12),
                                      Text('No se han encontrado jugadores para el equipo',
                                          style: TextStyle(fontSize: 16, color: Colors.grey)),
                                    ],
                                  ),
                                )
                              : ListView(
                                  children: [
                                    ...activos.map(_buildPlayerCard),
                                    if (bajas.isNotEmpty)
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                                        child: Text('Bajas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                      ),
                                    ...bajas.map(_buildPlayerCard),
                                  ],
                                ),
                  // Partidos
                  errorPartidos != null
                      ? Center(child: Text('Error al cargar partidos: \$errorPartidos'))
                      : isLoadingPartidos
                          ? const Center(child: CircularProgressIndicator())
                          : partidos.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(Icons.event_busy, size: 48, color: Colors.grey),
                                      SizedBox(height: 12),
                                      Text('No se han encontrado partidos para el equipo',
                                          style: TextStyle(fontSize: 16, color: Colors.grey)),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: partidos.length,
                                  itemBuilder: (context, index) {
                                    return _buildMatchCard(partidos[index]);
                                  },
                                ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: const ZocaloPublicitario(), // ✅ Zócalo insertado
      ),
    );
  }
}