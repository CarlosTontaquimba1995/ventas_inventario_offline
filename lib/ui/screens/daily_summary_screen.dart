import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../data/local/database.dart';
import '../../data/services/services/sync_service.dart';

class DailySummaryScreen extends StatefulWidget {
  const DailySummaryScreen({super.key});

  @override
  State<DailySummaryScreen> createState() => _DailySummaryScreenState();
}

class _DailySummaryScreenState extends State<DailySummaryScreen> {
  bool _isSyncing = false;

  Future<void> _handleSync(SyncService syncService) async {
    setState(() => _isSyncing = true);
    try {
      await syncService.sincronizacionCompletaSegura();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Sincronización exitosa')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<AppDatabase>(context);
    final syncService = Provider.of<SyncService>(context, listen: false);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Cierre y Cartera de Clientes',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.blueGrey[900],
          foregroundColor: Colors.white,
          bottom: const TabBar(
            indicatorColor: Colors.orangeAccent,
            indicatorWeight: 4,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            tabs: [
              Tab(icon: Icon(Icons.receipt_long), text: "VENTAS HOY"),
              Tab(icon: Icon(Icons.inventory), text: "ARTÍCULOS HOY"),
              Tab(icon: Icon(Icons.person_search), text: "CARTERA (DEUDAS)"),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: StreamBuilder<int>(
                stream: db.watchConteoPendientes(),
                builder: (context, snapshot) {
                  final pendientes = snapshot.data ?? 0;
                  final bool tienePendientes = pendientes > 0;
                  
                  return ElevatedButton.icon(
                    onPressed: (tienePendientes && !_isSyncing)
                        ? () => _handleSync(syncService)
                        : null,
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(
                            Icons.cloud_upload,
                            color: tienePendientes
                                ? Colors.white
                                : Colors.white38,
                          ),
                    label: Text(
                      _isSyncing ? 'ESPERE...' : 'SINCRONIZAR ($pendientes)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: tienePendientes ? Colors.white : Colors.white38,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tienePendientes
                          ? Colors.blue
                          : Colors.blueGrey[700],
                      disabledBackgroundColor: _isSyncing
                          ? Colors.blue
                          : Colors.blueGrey[800],
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
            _buildVistaCartera(db),
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
        if (ventas.isEmpty) {
          return const Center(child: Text("No hay ventas hoy"));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: ventas.length,
          itemBuilder: (context, index) {
            final item = ventas[index];
            return Card(
              child: ExpansionTile(
                title: Text('Ticket #${item.venta.id.substring(0, 5).toUpperCase()}'),
                subtitle: Text(
                  'Efectivo: \$${item.efectivoReal.toStringAsFixed(2)} | Deuda: \$${item.deudaPendiente.toStringAsFixed(2)}',
                ),
                children: item.desglosePorProducto.map((d) => ListTile(
                  dense: true,
                  title: Text("${d.cantidad}x ${d.nombre}"),
                        trailing: Text(
                          d.fuePagado ? "PAGADO" : "FIADO",
                          style: TextStyle(
                            color: d.fuePagado ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
        double totalEfectivo = 0;
        double totalFiado = 0;
        double totalGanancia = 0;
        for (var i in resumen) {
          double totalT = i.capitalTotal + i.gananciaTotal;
          double factor = totalT > 0 ? (totalT - i.deudaPendiente) / totalT : 0;
          totalEfectivo += (totalT - i.deudaPendiente);
          totalFiado += i.deudaPendiente;
          totalGanancia += i.gananciaTotal * factor;
        }
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              color: Colors.blueGrey[800],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _columnaTotal("EN CAJA", totalEfectivo, Colors.greenAccent),
                  _columnaTotal("FIADOS", totalFiado, Colors.orangeAccent),
                  _columnaTotal(
                    "GANANCIA REAL",
                    totalGanancia,
                    Colors.blueAccent,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 10),
                itemCount: resumen.length,
                separatorBuilder: (c, i) => const Divider(),
                itemBuilder: (context, index) {
                  final i = resumen[index];
                  double totalT = i.capitalTotal + i.gananciaTotal;
                  double factor = totalT > 0
                      ? (totalT - i.deudaPendiente) / totalT
                      : 0;
                  double gananciaEnCaja = i.gananciaTotal * factor;
                  double capitalEnCaja = i.capitalTotal * factor;

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 15,
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.blueGrey[100],
                          radius: 18,
                          child: Text(
                            '${i.cantidadTotal}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                i.nombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Caja: \$${(totalT - i.deudaPendiente).toStringAsFixed(2)}",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              "+\$${gananciaEnCaja.toStringAsFixed(2)} Ganancia",
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "\$${capitalEnCaja.toStringAsFixed(2)} Capital",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 11,
                              ),
                            ),
                            if (i.deudaPendiente > 0)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red[50],
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "Debe: \$${i.deudaPendiente.toStringAsFixed(2)}",
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildVistaCartera(AppDatabase db) {
    return StreamBuilder<List<VentaConDetalles>>(
      stream: db.watchCarteraFiadosPendientes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final fiados = snapshot.data!;
        if (fiados.isEmpty) {
          return const Center(child: Text("✅ Todo pagado"));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(10),
          itemCount: fiados.length,
          itemBuilder: (context, index) {
            final v = fiados[index];
            return Card(
              color: Colors.orange[50],
              child: ExpansionTile(
                leading: const Icon(Icons.person, color: Colors.orange),
                title: Text(
                  "Deuda del ${DateFormat('dd MMM').format(v.venta.fecha)}",
                ),
                subtitle: Text(
                  "Resta: \$${v.deudaPendiente.toStringAsFixed(2)}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                children: v.desglosePorProducto
                    .where((d) => !d.fuePagado)
                    .map(
                      (d) => ListTile(
                        title: Text(d.nombre),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            await db.cobrarProductoFiado(d.detalleId);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✅ Cobro registrado'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                          child: const Text("COBRAR"),
                        ),
                      ),
                    )
                    .toList(),
              ),
            );
          },
        );
      },
    );
  }

  Widget _columnaTotal(String t, double v, Color c) {
    return Column(
      children: [
        Text(t, style: const TextStyle(color: Colors.white70, fontSize: 10)),
        Text(
          '\$${v.toStringAsFixed(2)}',
          style: TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}