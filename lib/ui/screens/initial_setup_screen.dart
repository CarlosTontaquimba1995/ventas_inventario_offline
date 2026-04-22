import 'package:flutter/material.dart';
import 'package:ventas_inventario_offline/data/services/services/sync_service.dart';
import 'pos_screen.dart';

class InitialSetupScreen extends StatefulWidget {
  final SyncService syncService;
  const InitialSetupScreen({super.key, required this.syncService});

  @override
  State<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends State<InitialSetupScreen> {
  bool _isLoading = false;
  String _errorMessage = '';

  Future<void> _startSync() async {
    setState(() { _isLoading = true; _errorMessage = ''; });
    try {
      await widget.syncService.descargarCatalogoDesdeNube();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const PosScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "No se pudo conectar a la nube. Verifica el Wi-Fi.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_download, size: 100, color: Colors.blue),
              const SizedBox(height: 20),
              const Text(
                "Configuración Inicial",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "Necesitamos internet solo esta vez para descargar tus productos reales.",
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              if (_isLoading)
                const CircularProgressIndicator()
              else ...[
                if (_errorMessage.isNotEmpty)
                  Text(_errorMessage, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _startSync,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(200, 50)),
                  child: const Text("DESCARGAR PRODUCTOS"),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}