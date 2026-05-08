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
              child: StreamBuilder<List<Venta>>(
                stream: db.watchVentasPendientes(),
                builder: (context, snapshot) {
                  final pendientes = snapshot.data?.length ?? 0;
                  final bool tienePendientes = pendientes > 0;

                  return ElevatedButton.icon(
                    onPressed: tienePendientes 
                        ? () => syncService.sincronizacionCompletaSegura() 
                        : null,
                    icon: Icon(
                      Icons.cloud_upload,
                      color: tienePendientes
                          ? Colors.white
                          : const Color.fromARGB(151, 255, 255, 255),
                    ),
                    label: Text(
                      'SINCRONIZAR ($pendientes)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: tienePendientes
                            ? Colors.white
                            : const Color.fromARGB(151, 255, 255, 255),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tienePendientes
                          ? Colors.blue
                          : Colors.blueGrey[700],
                      disabledBackgroundColor: Colors.blueGrey[800],
                      elevation: tienePendientes ? 4 : 0,
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
        if (ventas.isEmpty)
          return const Center(child: Text("No hay ventas hoy"));
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
        
        double totalEfectivoCaja = 0;
        double totalFiadosPendientes = 0;
        double totalGananciaRealEnMano = 0;

        for (var item in resumen) {
          double ventaTotalTeorica = item.capitalTotal + item.gananciaTotal;
          double pagadoEfectivo = ventaTotalTeorica - item.deudaPendiente;
          double factorCobrado = (ventaTotalTeorica > 0)
              ? (pagadoEfectivo / ventaTotalTeorica)
              : 0;

          totalEfectivoCaja += pagadoEfectivo;
          totalFiadosPendientes += item.deudaPendiente;
          totalGananciaRealEnMano += item.gananciaTotal * factorCobrado;
        }

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              color: Colors.blueGrey[800],
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _columnaTotal(
                    "EN CAJA",
                    totalEfectivoCaja,
                    Colors.greenAccent,
                  ),
                  _columnaTotal(
                    "FIADOS",
                    totalFiadosPendientes,
                    Colors.orangeAccent,
                  ),
                  _columnaTotal(
                    "GANANCIA REAL",
                    totalGananciaRealEnMano,
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
                  final item = resumen[index];
                  double ventaTotalTeorica =
                      item.capitalTotal + item.gananciaTotal;
                  double pagadoEfectivo =
                      ventaTotalTeorica - item.deudaPendiente;
                  double factorCobrado = (ventaTotalTeorica > 0)
                      ? (pagadoEfectivo / ventaTotalTeorica)
                      : 0;

                  double gananciaEnCaja = item.gananciaTotal * factorCobrado;
                  double capitalEnCaja = item.capitalTotal * factorCobrado;

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.blueGrey[100],
                          radius: 18,
                          child: Text(
                            '${item.cantidadTotal}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blueGrey,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.nombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "En Caja: \$${pagadoEfectivo.toStringAsFixed(2)}",
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
                            if (item.deudaPendiente > 0)
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
                                  "Debe: \$${item.deudaPendiente.toStringAsFixed(2)}",
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
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final fiados = snapshot.data!;
        if (fiados.isEmpty) return const Center(child: Text("✅ Todo pagado"));

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
                        subtitle: Text(
                          "\$${d.precioVentaUnitario.toStringAsFixed(2)}",
                        ),
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await db.cobrarProductoFiado(d.detalleId);
                            if (!mounted) return;
                            setState(() {});
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('✅ Cobro registrado'),
                                backgroundColor: Colors.green,
                              ),
                            );
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