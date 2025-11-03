import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'team_detail_screen.dart';
import '../services/remote_data_service.dart';
import 'package:http/http.dart' as http;
import '../widgets/zocalo_publicitario.dart';


class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key});

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> with SingleTickerProviderStateMixin {
  List<dynamic> equiposTemporada = [];
  List<dynamic> equiposHistoricos = [];
  bool isLoading = false;
  String? error;
  String? equiposAdUrl;
  bool initialLoading = true;
  String searchQuery = '';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);

    RemoteDataService.fetchAdImages().then((ads) {
      if (!mounted) return;
      setState(() {
        //equiposAdUrl = ads['equipos'];
      });
    });

    _loadFromCacheThenFetch();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFromCacheThenFetch() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      initialLoading = true;
    });

    final actuales = await _loadCache('cache_equipos_actuales');
    final historicos = await _loadCache('cache_equipos_historicos');

    if (!mounted) return;
    if (actuales != null) {
      setState(() {
        equiposTemporada = actuales;
      });
    }

    if (historicos != null) {
      equiposHistoricos = historicos;
    }

    if (!mounted) return;
    setState(() {
      isLoading = false;
      initialLoading = false;
    });

    _fetchEquiposTemporadaActual();
  }

  Future<void> _fetchEquiposTemporadaActual() async {
    try {
      final excludedIds = await fetchEquiposExcluidos();
      final all = (await ApiService.getEquipos(temporada: 196))
          .where((e) => !excludedIds.contains(e["id"]))
          .toList()
        ..sort((a, b) => (a['nombre'] ?? '').toString().toLowerCase().compareTo((b['nombre'] ?? '').toString().toLowerCase()));

      await _saveCache('cache_equipos_actuales', all);
      if (!mounted) return;
      setState(() {
        equiposTemporada = all;
      });
      _fetchEquiposHistoricos();
    } catch (e) {
      if (!mounted) return;
      setState(() => error = e.toString());
    }
  }

  Future<void> _fetchEquiposHistoricos() async {
    try {
      final excludedIds = await fetchEquiposExcluidos();
      final all = (await ApiService.getEquipos())
          .where((e) => !excludedIds.contains(e["id"]))
          .toList();

      final actualesIds = equiposTemporada.map((e) => e['id']).toSet();
      final historicos = all.where((e) {
        final temporadas = List.from(e['temporadas'] ?? []);
        final noEsActual = !temporadas.contains(196);
        final noEsDuplicado = !actualesIds.contains(e['id']);
        return noEsActual && noEsDuplicado;
      }).toList()
        ..sort((a, b) => (a['nombre'] ?? '').toString().toLowerCase().compareTo((b['nombre'] ?? '').toString().toLowerCase()));

      if (!mounted) return;
      setState(() {
        equiposHistoricos = historicos;
      });

      await _saveCache('cache_equipos_historicos', historicos);
    } catch (e) {
      if (!mounted) return;
      setState(() => error = 'Error al cargar equipos históricos: $e');
    }
  }

  Future<void> _saveCache(String key, List<dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    };
    await prefs.setString(key, jsonEncode(payload));
  }

  Future<List<dynamic>?> _loadCache(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw != null) {
      final decoded = jsonDecode(raw);
      final timestamp = decoded['timestamp'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;
      final cacheAge = key == 'cache_equipos_historicos' ? 7 * 86400000 : 3600000;
      if ((now - timestamp) < cacheAge) {
        return List<dynamic>.from(decoded['data']);
      }
    }
    return null;
  }

  List<dynamic> _filteredEquipos(List<dynamic> equipos) {
    if (searchQuery.isEmpty) return equipos;
    return equipos.where((e) {
      final nombre = (e['nombre'] ?? '').toString().toLowerCase();
      return nombre.contains(searchQuery.toLowerCase());
    }).toList();
  }

  Widget _buildTeamCard(dynamic team) {
    final nombre = team['nombre'] ?? 'Sin nombre';
    final avatarRaw = team['imagen'];
    final avatar = (avatarRaw is String && avatarRaw.isNotEmpty) ? avatarRaw : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: avatar != null ? NetworkImage(avatar) : null,
          backgroundColor: Colors.grey[300],
          child: avatar == null ? const Icon(Icons.shield) : null,
        ),
        title: Text(nombre, overflow: TextOverflow.ellipsis),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => TeamDetailScreen(team: team)),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Equipos'), centerTitle: true),
        body: Column(
          children: [
            TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Theme.of(context).primaryColor,
              tabs: const [
                Tab(text: 'Temporada Actual'),
                Tab(text: 'Histórico'),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Buscar equipo',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) {
                  setState(() {
                    searchQuery = value;
                  });
                },
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Temporada Actual
                  error != null
                      ? Center(child: Text('Error: $error'))
                      : (initialLoading && equiposTemporada.isEmpty)
                          ? LoadingSeccionConAd(
                              texto: 'Cargando equipos...',
                              adImageUrl: equiposAdUrl,
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: _filteredEquipos(equiposTemporada).length,
                              itemBuilder: (context, index) {
                                final filtered = _filteredEquipos(equiposTemporada);
                                return _buildTeamCard(filtered[index]);
                              },
                            ),

                  // Histórico
                  ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _filteredEquipos(equiposHistoricos).length,
                    itemBuilder: (context, index) {
                      final filtered = _filteredEquipos(equiposHistoricos);
                      return _buildTeamCard(filtered[index]);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: const ZocaloPublicitario(), // ✅ Aquí se inserta el zócalo
      ),
    );
  }

  Future<List<int>> fetchEquiposExcluidos() async {
    final url = Uri.parse('https://entreredespadres.com.ar/wp-content/uploads/media/listas_jugadores.json');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final ids = [
          ...(data['lista_reserva'] ?? []),
          ...(data['lista_espera'] ?? []),
          ...(data['lista_no_inscriptos'] ?? []),
        ];
        return List<int>.from(ids.whereType<int>());
      }
    } catch (e) {
      debugPrint("No se pudo cargar el JSON de exclusión: $e");
    }
    return [];
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