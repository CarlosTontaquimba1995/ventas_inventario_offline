import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/local/database.dart';
import '../../data/services/services/sync_service.dart';

class DailySummaryScreen extends StatelessWidget {
  const DailySummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<AppDatabase>(context);
    final syncService = Provider.of<SyncService>(context, listen: false);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cierre de Caja'),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            tabs: [
              Tab(icon: Icon(Icons.receipt_long), text: "POR VENTAS"),
              Tab(icon: Icon(Icons.inventory), text: "POR PRODUCTOS"),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: StreamBuilder<List<Venta>>(
                stream: db.watchVentasPendientes(),
                builder: (context, snapshot) {
                  final pendientes = snapshot.data?.length ?? 0;
                  return ElevatedButton.icon(
                    onPressed: pendientes > 0 
                        ? () => syncService.sincronizacionCompletaSegura() 
                        : null,
                    icon: const Icon(Icons.cloud_upload, color: Colors.white),
                    label: Text(
                      'SINCRONIZAR ($pendientes)', 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: pendientes > 0 ? Colors.blue : Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            _buildVistaVentas(db),
            _buildVistaProductosGlobal(db),
          ],
        ),
      ),
    );
  }

  Widget _buildVistaVentas(AppDatabase db) {
    return StreamBuilder<List<VentaConDetalles>>(
      stream: db.watchVentasDelDiaDetalladas(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final ventas = snapshot.data!;

        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: ventas.length,
          itemBuilder: (context, index) {
            final item = ventas[index];
            return Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: item.venta.sincronizado ? Colors.blue.shade100 : Colors.orange.shade200),
              ),
              child: ExpansionTile(
                leading: Icon(item.venta.sincronizado ? Icons.cloud_done : Icons.cloud_off, 
                             color: item.venta.sincronizado ? Colors.blue : Colors.orange),
                title: Text('Ticket #${item.venta.id.substring(0, 5).toUpperCase()}'),
                subtitle: Text('Ganancia: \$${item.gananciaTotalVenta.toStringAsFixed(2)}'),
                trailing: Text('\$${item.venta.total.toStringAsFixed(2)}', 
                               style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                children: item.desglosePorProducto.map((d) => ListTile(
                  dense: true,
                  title: Text("${d.cantidad}x ${d.nombre}"),
                  subtitle: Text("Cap: \$${d.capitalTotalFila.toStringAsFixed(2)} | Gan: \$${d.gananciaTotalFila.toStringAsFixed(2)}"),
                )).toList(),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildVistaProductosGlobal(AppDatabase db) {
    return StreamBuilder<List<ResumenProductoGlobal>>(
      stream: db.watchResumenGlobalHoy(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final resumen = snapshot.data!;
        
        double totalCap = resumen.fold(0, (s, i) => s + i.capitalTotal);
        double totalGan = resumen.fold(0, (s, i) => s + i.gananciaTotal);

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              color: Colors.blueGrey.shade900,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _columnaTotal("CAPITAL TOTAL", totalCap, Colors.orangeAccent),
                  _columnaTotal("GANANCIA TOTAL", totalGan, Colors.greenAccent),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text("DESGLOSE POR ARTÍCULO", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: resumen.length,
                separatorBuilder: (c, i) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = resumen[index];
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: Colors.blue.shade50, 
                                        child: Text('${item.cantidadTotal}', style: const TextStyle(fontSize: 12))),
                    title: Text(item.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text("Capital: \$${item.capitalTotal.toStringAsFixed(2)}"),
                    trailing: Text("Ganancia: \$${item.gananciaTotal.toStringAsFixed(2)}", 
                                   style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _columnaTotal(String t, double v, Color c) {
    return Column(
      children: [
        Text(t, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        Text('\$${v.toStringAsFixed(2)}', style: TextStyle(color: c, fontSize: 22, fontWeight: FontWeight.bold)),
      ],
    );
  }
}