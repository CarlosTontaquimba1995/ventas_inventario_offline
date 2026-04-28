import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventas_inventario_offline/data/services/services/sync_service.dart';
import 'data/local/database.dart';
import 'ui/screens/pos_screen.dart';
import 'ui/screens/initial_setup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://wejssxwahwipcahsyyen.supabase.co',
    anonKey: 'sb_publishable_p4ZDtVowA3QS5bwMpXFv1w_GUgDPJwJ',
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  final database = AppDatabase();
  final syncService = SyncService(database);
  final productosLocales = await database.select(database.productos).get();
  final bool necesitaConfiguracion = productosLocales.isEmpty;

  runApp(
    Provider<AppDatabase>(
      create: (context) => database,
      dispose: (context, db) => db.close(),
      child: MultiProvider(
        providers: [Provider<SyncService>(create: (_) => syncService)],
        child: MaterialApp(
          title: 'Sistema de Ventas Offline',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: Colors.blue,
            brightness: Brightness.light,
          ),
          home: necesitaConfiguracion
              ? InitialSetupScreen(syncService: syncService)
              : const PosScreen(),
        ),
      ),
    ),
  );
}
