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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cierre de Caja Diario'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: StreamBuilder<List<Venta>>(
              stream: db.watchVentasPendientes(),
              builder: (context, snapshot) {
                final pendientes = snapshot.data?.length ?? 0;
                return ElevatedButton.icon(
                  onPressed: pendientes > 0 ? () => syncService.sincronizacionCompletaSegura() : null,
                  icon: const Icon(Icons.cloud_upload),
                  label: Text('SINCRONIZAR ($pendientes)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<VentaConDetalles>>(
        stream: db.watchVentasDelDiaDetalladas(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          
          final ventas = snapshot.data!;
          final totalVendido = ventas.fold(0.0, (sum, v) => sum + v.venta.total);
          final totalCapital = ventas.fold(0.0, (sum, v) => sum + v.capitalTotalVenta);
          final totalGanancia = totalVendido - totalCapital;

          return Column(
            children: [
              _buildHeaderFinanciero(totalVendido, totalCapital, totalGanancia, ventas.length),
              
              const Divider(height: 1),
              
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(top: 10, bottom: 30),
                  itemCount: ventas.length,
                  itemBuilder: (context, index) {
                    final item = ventas[index];
                    final isSincro = item.venta.sincronizado;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: BorderSide(color: isSincro ? Colors.grey.shade200 : Colors.orange.shade300, width: 2),
                      ),
                      child: ExpansionTile(
                        leading: Icon(
                          isSincro ? Icons.cloud_done : Icons.cloud_off,
                          color: isSincro ? Colors.blue : Colors.orange,
                          size: 32,
                        ),
                        title: Text('Venta #${item.venta.id.substring(0, 5).toUpperCase()}', 
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Ganancia Venta: \$${item.gananciaTotalVenta.toStringAsFixed(2)}'),
                        trailing: Text('\$${item.venta.total.toStringAsFixed(2)}', 
                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(15),
                            color: Colors.blueGrey.shade50,
                            child: Column(
                              children: item.desglosePorProducto.map((d) => _buildFilaDetallada(d)).toList(),
                            ),
                          )
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilaDetallada(DetalleConCalculo d) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("${d.cantidad}x ${d.nombre}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text("\$${(d.precioVentaUnitario * d.cantidad).toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _etiquetaFinanciera("Capital: \$${d.capitalTotalFila.toStringAsFixed(2)}", Colors.orange),
              const SizedBox(width: 15),
              _etiquetaFinanciera("Ganancia: \$${d.gananciaTotalFila.toStringAsFixed(2)}", Colors.green),
            ],
          ),
          const Divider(),
        ],
      ),
    );
  }

  Widget _etiquetaFinanciera(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(5)),
      child: Text(texto, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildHeaderFinanciero(double v, double c, double g, int cant) {
    return Container(
      padding: const EdgeInsets.all(25),
      color: Colors.blueGrey.shade900,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildDatoHeader("VENTAS", v, Colors.blueAccent),
          _buildDatoHeader("CAPITAL", c, Colors.orangeAccent),
          _buildDatoHeader("GANANCIA", g, Colors.greenAccent),
        ],
      ),
    );
  }

  Widget _buildDatoHeader(String t, double v, Color c) {
    return Column(
      children: [
        Text(t, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
        Text("\$${v.toStringAsFixed(2)}", style: TextStyle(color: c, fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }
}