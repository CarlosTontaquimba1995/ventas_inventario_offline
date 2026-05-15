import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' as d hide Column;
import 'package:uuid/uuid.dart'; 
import 'package:cached_network_image/cached_network_image.dart';
import '../../data/local/database.dart';
import '../../data/services/services/sync_service.dart';
import 'daily_summary_screen.dart';

class CartItem {
  final Producto producto;
  bool pagado;
  CartItem({required this.producto, this.pagado = true});
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  String _searchQuery = '';
  final List<CartItem> _cart = []; 
  bool _showSuccessMessage = false;
  String? _errorMessage;
  
  final _uuid = const Uuid();

  Color _getColorSemaforo(int stock) {
    if (stock <= 5) return Colors.red;
    if (stock <= 15) return Colors.orange;
    return Colors.green;
  }

  Future<void> _ejecutarSyncTotal(BuildContext contextParam) async {
    if (_cart.isNotEmpty) {
      ScaffoldMessenger.of(contextParam).showSnackBar(
        const SnackBar(
          content: Text('Limpia el carrito antes de sincronizar.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final syncService = Provider.of<SyncService>(contextParam, listen: false);
    showDialog(
      context: contextParam,
      barrierDismissible: false,
      builder: (c) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text("Actualizando inventario..."),
          ],
        ),
      ),
    );

    try {
      await syncService.sincronizacionCompletaSegura();
      if (!contextParam.mounted) return;
      Navigator.of(contextParam).pop();
      ScaffoldMessenger.of(contextParam).showSnackBar(
        const SnackBar(content: Text('Base de datos actualizada')),
      );
    } catch (e) {
      if (!contextParam.mounted) return;
      Navigator.of(contextParam).pop();
      ScaffoldMessenger.of(contextParam).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
      );
    }
  }

  void _mostrarNotificacionExito() {
    setState(() {
      _showSuccessMessage = true;
      _errorMessage = null;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showSuccessMessage = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final db = Provider.of<AppDatabase>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('SISTEMA DE VENTAS', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, size: 28),
            onPressed: () => _ejecutarSyncTotal(context),
          ),
          IconButton(
            icon: const Icon(Icons.analytics_outlined, size: 30),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (c) => const DailySummaryScreen()),
            ),
          ),
          const SizedBox(width: 10),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar producto...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Expanded(
                  child: StreamBuilder<List<Producto>>(
                    stream: _searchQuery.isEmpty 
                      ? db.watchProductosOrdenadosPorVentas() 
                      : (db.select(db.productos)..where((p) => p.nombre.lower().contains(_searchQuery.toLowerCase()))).watch(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text("Error: ${snapshot.error}"));
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      
                      final productos = snapshot.data!;
                      return GridView.builder(
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, 
                              childAspectRatio: 0.82,
                              crossAxisSpacing: 12, 
                          mainAxisSpacing: 12
                        ),
                        itemCount: productos.length,
                        itemBuilder: (context, i) {
                          final p = productos[i];
                          return Card(
                            clipBehavior: Clip.antiAlias,
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                              side: BorderSide(
                                color: _getColorSemaforo(p.stockLocal),
                                width: 2,
                              ),
                            ),
                            child: InkWell(
                              onTap: p.stockLocal > 0
                                  ? () => setState(
                                      () => _cart.add(CartItem(producto: p)),
                                    )
                                  : null,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 5, 
                                    child: Container(
                                      color: Colors.white,
                                      child:
                                          (p.imagenUrl != null &&
                                              p.imagenUrl!.isNotEmpty) 
                                        ? CachedNetworkImage(
                                              imageUrl: p.imagenUrl!, 
                                            fit: BoxFit.contain,
                                            placeholder: (c, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                            errorWidget: (c, url, e) => const Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
                                          )
                                          : Container(
                                              color: Colors.grey[100],
                                              child: const Icon(
                                                Icons.inventory_2_outlined,
                                                size: 40,
                                                color: Colors.grey,
                                              ),
                                            ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 4, 
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center, 
                                        children: [
                                          Text(
                                            p.nombre,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                            textAlign: TextAlign.center,
                                            maxLines: 2,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '\$${p.precio.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              fontSize: 18,
                                              color: Colors.green,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            'Stock: ${p.stockLocal}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: _getColorSemaforo(
                                                p.stockLocal,
                                              ),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                _buildPanelNotificaciones(),
              ],
            ),
          ),
          _buildCarrito(context),
        ],
      ),
    );
  }

  Widget _buildCarrito(BuildContext context) {
    final total = _cart.fold(0.0, (s, item) => s + item.producto.precio);
    return Container(
      width: 380,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Colors.black12)),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 25),
            child: Text(
              'DETALLE DE VENTA',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: ListView.separated(
              itemCount: _cart.length,
              separatorBuilder: (c, i) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = _cart[i];
                return Container(
                  height:
                      70,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.producto.nombre,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '\$${item.producto.precio.toStringAsFixed(2)}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(
                        width: 65,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              item.pagado
                                  ? Icons.check_circle
                                  : Icons.warning_amber_rounded,
                              color: item.pagado ? Colors.green : Colors.orange,
                              size: 22,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.pagado ? "PAGADO" : "FIADO",
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                                color: item.pagado
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),

                      Center(
                        child: Transform.scale(
                          scale:
                              0.8,
                          child: Switch(
                            value: item.pagado,
                            activeThumbColor: Colors.green,
                            onChanged: (v) => setState(() => item.pagado = v),
                          ),
                        ),
                      ),

                      IconButton(
                        onPressed: () => setState(() => _cart.removeAt(i)),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.redAccent,
                          size: 22,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(25),
            color: Colors.blueGrey[50],
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL:',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '\$${total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  height: 65,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                    onPressed: _cart.isEmpty ? null : () => _finalizarVenta(context),
                    child: const Text(
                      'FINALIZAR COBRO',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildPanelNotificaciones() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: (_showSuccessMessage || _errorMessage != null) ? 60 : 0,
      width: double.infinity,
      color: _showSuccessMessage ? Colors.green : Colors.redAccent,
      child: Center(
        child: Text(
          _showSuccessMessage ? '✅ VENTA REGISTRADA' : (_errorMessage ?? ''),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Future<void> _finalizarVenta(BuildContext context) async {
    final db = Provider.of<AppDatabase>(context, listen: false);
    final String idVenta = _uuid.v4(); 
    final double montoTotal = _cart.fold(0.0, (s, i) => s + i.producto.precio);
    
    try {
      await db.registrarVentaCompleta(
        VentasCompanion.insert(
          id: idVenta,
          total: montoTotal,
          fecha: DateTime.now(),
          sincronizado: const d.Value(false),
        ),
        _cart
            .map(
              (item) => VentaDetallesCompanion.insert(
          ventaId: idVenta,
                productoId: item.producto.id,
          cantidad: 1,
                precioUnitario: item.producto.precio,
                pagado: d.Value(item.pagado), 
        )).toList()
      );
      if (!mounted) return;
      setState(() => _cart.clear());
      _mostrarNotificacionExito();
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = "Error: $e");
    }
  }
}