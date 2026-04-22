import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:ventas_inventario_offline/data/services/services/sync_service.dart';
import 'package:ventas_inventario_offline/models/venta_con_detalles.dart';
import '../../data/local/database.dart';

class DailySummaryScreen extends StatefulWidget {
  const DailySummaryScreen({super.key});

  @override
  State<DailySummaryScreen> createState() => _DailySummaryScreenState();
}

class _DailySummaryScreenState extends State<DailySummaryScreen> {
  bool _isSyncing = false;
  bool _verSoloPendientes = false;

  Future<void> _ejecutarSincronizacion(BuildContext contextParam) async {
    final syncService = Provider.of<SyncService>(contextParam, listen: false);
    setState(() => _isSyncing = true);

    try {
      await syncService.sincronizarVentas();
      if (!mounted || !context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('✅ Sincronización Exitosa')));
    } catch (e) {
      if (!mounted || !context.mounted) return;

      String mensaje = '❌ No se pudo sincronizar. ';
      if (e.toString().contains('SocketException') ||
          e.toString().contains('host lookup')) {
        mensaje += 'Revisa tu conexión a internet.';
      } else {
        mensaje += 'Error: $e';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(mensaje), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<AppDatabase>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cierre de Caja Diario'),
        actions: [
          StreamBuilder<int>(
            stream: db.watchVentasPendientesCount(),
            builder: (context, snapshot) {
              final pendientes = snapshot.data ?? 0;

              if (_isSyncing) {
                return const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 15),
                  child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                );
              }

              if (pendientes == 0) {
                return const Padding(
                  padding: EdgeInsets.only(right: 15),
                  child: Icon(Icons.cloud_done, color: Colors.green),
                );
              }

              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: ElevatedButton.icon(
                  onPressed: () => _ejecutarSincronizacion(context),
                  icon: const Icon(Icons.cloud_upload),
                  label: Text('SINCRONIZAR ($pendientes)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          StreamBuilder<List<VentaConDetalles>>(
            stream: db.watchVentasHoyConDetalles(),
            builder: (context, snapshot) {
              final ventas = snapshot.data ?? [];
              final total = ventas.fold(0.0, (s, item) => s + item.venta.total);
              
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(25),
                color: Colors.blue.shade50,
                child: Column(
                  children: [
                    const Text('TOTAL VENDIDO HOY', style: TextStyle(fontWeight: FontWeight.w600)),
                    Text('\$${total.toStringAsFixed(2)}', 
                         style: const TextStyle(fontSize: 45, fontWeight: FontWeight.bold, color: Colors.blue)),
                    Text('${ventas.length} ventas realizadas'),
                  ],
                ),
              );
            },
          ),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(value: false, label: Text('Todas'), icon: Icon(Icons.list)),
                ButtonSegment<bool>(value: true, label: Text('Solo Pendientes'), icon: Icon(Icons.cloud_off)),
              ],
              selected: {_verSoloPendientes},
              onSelectionChanged: (Set<bool> selection) {
                setState(() => _verSoloPendientes = selection.first);
              },
            ),
          ),
          
          Expanded(
            child: StreamBuilder<List<VentaConDetalles>>(
              stream: db.watchVentasHoyConDetalles(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final todas = snapshot.data!;
                final filtradas = _verSoloPendientes 
                    ? todas.where((v) => v.venta.sincronizado == false).toList()
                    : todas;

                return ListView.builder(
                  itemCount: filtradas.length,
                  itemBuilder: (context, index) {
                    final item = filtradas[index];
                    final bool isSincro = item.venta.sincronizado;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isSincro ? Colors.transparent : Colors.orange,
                          width: 1,
                        ),
                      ),
                      child: ExpansionTile(
                        leading: Icon(
                          isSincro ? Icons.cloud_done : Icons.cloud_off, 
                          color: isSincro ? Colors.green : Colors.orange
                        ),
                        title: Text('Venta #${item.venta.id.substring(0, 5)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(DateFormat('hh:mm a').format(item.venta.fecha)),
                        trailing: Text('\$${item.venta.total.toStringAsFixed(2)}', 
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green)),
                        children: [
                          Container(
                            color: Colors.grey.shade50,
                            child: Column(
                              children: item.detallesFormateados.map((d) => ListTile(
                                dense: true,
                                leading: const Icon(Icons.arrow_right, size: 18),
                                title: Text(d),
                              )).toList(),
                            ),
                          )
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}