import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/players_screen.dart';
import 'screens/standings_screen.dart';
import 'screens/teams_screen.dart';
import 'screens/more_screen.dart';
import 'services/cache_service.dart';
import 'screens/matches_screen.dart' show MatchesScreen, temporadaActualId;


  void main() async {
    WidgetsFlutterBinding.ensureInitialized();
    await CacheService.clearCacheOncePerWeekWindow();
    runApp(const EntreRedesApp());
  }

  class EntreRedesApp extends StatelessWidget {
    const EntreRedesApp({super.key});

    @override
    Widget build(BuildContext context) {
      return MaterialApp(
        title: 'Entre Redes',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan).copyWith(
            primary: const Color(0xFF005BBB),
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF005BBB),
            foregroundColor: Colors.white,
            iconTheme: IconThemeData(color: Colors.white),
            titleTextStyle: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        home: const SplashToMain(), // 👈 Nuevo widget inicial
      );
    }
  }

  class SplashToMain extends StatefulWidget {
    const SplashToMain({super.key});

    @override
    State<SplashToMain> createState() => _SplashToMainState();

  }

  class _SplashToMainState extends State<SplashToMain> {
    @override
    void initState() {
      super.initState();
      Future.delayed(const Duration(milliseconds: 100), () {
      Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => const MainNavigation(),
      ));
      });
    }

    @override
    Widget build(BuildContext context) {
      return const Scaffold(
        backgroundColor: Color(0xFF005BBB),
        body: Center(
          child: SizedBox.shrink(), // vacío para no interferir con el storyboard
        ),
      );
    }
  }

  class MainNavigation extends StatefulWidget {
    const MainNavigation({super.key});

    @override
    State<MainNavigation> createState() => _MainNavigationState();
  }

  class _MainNavigationState extends State<MainNavigation> {
    int _selectedIndex = 0;

    late final List<Widget> _screens;

    @override
    void initState() {
      super.initState();
      _screens = [
        MatchesScreen(temporadaId: temporadaActualId),
        const StandingsScreen(),
        const TeamsScreen(),
        const PlayersScreen(),
        const MoreScreen(),
      ];
    }

    void _onItemTapped(int index) {
      setState(() {
        _selectedIndex = index;
      });
    }

    @override
    Widget build(BuildContext context) {
      return Scaffold(
        body: _screens[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF005BBB),
          selectedItemColor: Colors.white,
          unselectedItemColor: Colors.white70,
          items: [
            _buildNavItem(0, Icons.sports_soccer, 'Partidos'),
            _buildNavItem(1, Icons.bar_chart, 'Posiciones'),
            _buildNavItem(2, Icons.group, 'Equipos'),
            _buildNavItem(3, Icons.person, 'Jugadores'),
            _buildNavItem(4, Icons.menu, 'Más'),
          ],
        )
      );
    }

    BottomNavigationBarItem _buildNavItem(int index, IconData icon, String label) {
      final isSelected = _selectedIndex == index;

      return BottomNavigationBarItem(
        label: label,
        icon: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          margin: const EdgeInsets.only(bottom: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 3,
                width: 24,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              AnimatedScale(
                scale: isSelected ? 1.2 : 1.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                child: Icon(icon),
              ),
            ],
          ),
        ),
      );
    }
  }