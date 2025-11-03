import 'package:flutter/material.dart';
import 'listas_screen.dart';
import 'scorers_screen.dart';
import 'imbatibles_screen.dart';
import '../services/cache_service.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'solicitud_cambio_webview.dart';


class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

  Widget _menuItem(String label, IconData icon, VoidCallback onTap) => ListTile(
        leading: Icon(icon, color: Colors.black),
        title: Text(label),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      );

  @override
  Widget build(BuildContext context) {
    void abrirPdf(String url) async {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('No se pudo abrir $url');
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Otras Opciones')),
      body: ListView(
        children: [
          _sectionTitle('Estadísticas'),
          _menuItem(
            'Goleadores 2025',
            Icons.sports_soccer,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ScorersScreen()),
              );
            },
          ),
          _menuItem(
            'Imbatibles 2025',
            Icons.sports_handball,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ImbatiblesScreen()),
              );
            },
          ),

          _sectionTitle('Gestión Torneo'),
          _menuItem(
            'Solicitud de cambio de jugador',
            Icons.swap_horiz,
            () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SolicitudCambioWebViewScreen()),
            );
            },
          ),
          _menuItem(
            'Lista de Espera y Reserva 2025',
            Icons.people_alt,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ListasScreen()),
              );
            },
          ),
          //_menuItem('Cambios Solicitados y Realizados 2025', Icons.swap_horiz, () {}),
          //_menuItem('Suspendidos 2025', Icons.block, () {}),

          _sectionTitle('Información'),
          _menuItem(
            'Reglamento 2025',
            Icons.rule,
            () => abrirPdf('https://entreredespadres.com.ar/wp-content/uploads/REGLAMENTO-CHAMI-2025.pdf'),
          ),
          _menuItem(
            'Modalidad Torneo 2025',
            Icons.description,
            () => abrirPdf('https://entreredespadres.com.ar/wp-content/uploads/2025/modalidad_torneo_2025.pdf'),
          ),

          _sectionTitle('Anuarios'),
          _menuItem(
            'Anuario 2022',
            Icons.menu_book,
            () => abrirPdf('https://entreredespadres.com.ar/wp-content/uploads/Entreredes2022-Anuario.pdf'),
          ),
          _menuItem(
            'Anuario 2023',
            Icons.menu_book,
            () => abrirPdf('https://entreredespadres.com.ar/wp-content/uploads/Anuario-2023-OK.pdf'),
          ),
          _menuItem(
            'Anuario 2024',
            Icons.menu_book,
            () => abrirPdf('https://entreredespadres.com.ar/wp-content/uploads/Anuario-2024.pdf'),
          ),

          if (kDebugMode) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.delete_forever),
                label: const Text('Limpiar toda la caché'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  await CacheService.clearAllCaches();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Caché eliminada correctamente')),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}