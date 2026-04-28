import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' as d hide Column;
import 'package:uuid/uuid.dart'; 
import '../../data/local/database.dart';
import '../../data/services/services/sync_service.dart';
import 'daily_summary_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  String _searchQuery = '';
  final List<Producto> _cart = [];
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
          content: Text('⚠️ Termina o limpia el carrito antes de sincronizar.'),
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
            Text("Sincronizando con la nube..."),
          ],
        ),
      ),
    );

    try {
      await syncService.sincronizacionCompletaSegura();
      if (!mounted || !context.mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Sincronización exitosa')));
          
    } catch (e) {
      if (!mounted || !context.mounted) return;

      Navigator.of(context).pop();

      String mensajeAmigable = '❌ Ocurrió un error inesperado';
      final errorText = e.toString();

      if (errorText.contains('SocketException') || errorText.contains('Failed host lookup')) {
        mensajeAmigable = '📡 No hay conexión a internet. Revisa tu red.';
      } else if (errorText.contains('HttpException')) {
        mensajeAmigable = '☁️ Error al conectar con el servidor de la nube.';
      } else if (errorText.contains('timeout')) {
        mensajeAmigable = '⏱️ La conexión tardó demasiado.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensajeAmigable),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 4),
        ),
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
        title: const Text('SISTEMA DE VENTAS'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.sync,
              color: _cart.isNotEmpty ? Colors.grey : Colors.blue,
              size: 28,
            ),
            tooltip: 'Actualizar Stock y Productos',
            onPressed: () => _ejecutarSyncTotal(context),
          ),
          IconButton(
            icon: const Icon(Icons.analytics, size: 30),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (c) => const DailySummaryScreen()),
            ),
          )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
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
                        return Center(child: Text("Error en la base de datos: ${snapshot.error}"));
                      }
  
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
  
                      final productos = snapshot.data!;
                      
                      return GridView.builder(
                        padding: const EdgeInsets.all(10),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, 
                          childAspectRatio: 1.15,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10
                        ),
                        itemCount: productos.length,
                        itemBuilder: (context, i) {
                          final p = productos[i];
                          final colorSemaforo = _getColorSemaforo(p.stockLocal);
                          
                          return Card(
                            elevation: 3,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                              side: BorderSide(
                                color: colorSemaforo.withOpacity(0.4),
                                width: 2,
                              ),
                            ),
                            child: InkWell(
                              onTap: p.stockLocal > 0
                                  ? () => setState(() => _cart.add(p))
                                  : null,
                              child: Stack(
                                children: [
                                  Positioned(
                                    top: 10,
                                    right: 10,
                                    child: Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: colorSemaforo,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                                  Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          p.nombre,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                        ),
                                        Text(
                                          '\$${p.precio.toStringAsFixed(2)}',
                                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: colorSemaforo.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Text(
                                            'Stock: ${p.stockLocal}',
                                            style: TextStyle(
                                              color: colorSemaforo,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
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
    final total = _cart.fold(0.0, (s, item) => s + item.precio);
    return Container(
      width: 350,
      color: Colors.blueGrey[50],
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('DETALLE DE VENTA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _cart.length,
              itemBuilder: (context, i) => ListTile(
                title: Text(_cart[i].nombre),
                subtitle: Text('\$${_cart[i].precio.toStringAsFixed(2)}'),
                trailing: IconButton(
                  icon: const Icon(Icons.remove_circle, color: Colors.red),
                  onPressed: () => setState(() => _cart.removeAt(i)),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TOTAL:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Text(
                      '\$${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _cart.isEmpty ? null : () => _finalizarVenta(context),
                    child: const Text('COBRAR', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
      color: _showSuccessMessage ? Colors.green : Colors.red,
      child: Center(
        child: Text(
          _showSuccessMessage ? '¡Venta Exitosa!' : (_errorMessage ?? ''),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Future<void> _finalizarVenta(BuildContext context) async {
    final db = Provider.of<AppDatabase>(context, listen: false);
    
    final String id = _uuid.v4(); 
    
    try {
      await db.registrarVentaCompleta(
        VentasCompanion.insert(
          id: id,
          total: _cart.fold(0.0, (s, i) => s + i.precio),
          fecha: d.Value(DateTime.now()),
          sincronizado: const d.Value(false),
        ),
        _cart.map((p) => VentaDetallesCompanion.insert(
          ventaId: id,
          productoId: p.id,
          cantidad: 1,
          precioUnitario: p.precio,
        )).toList()
      );
      
      if (!mounted) return;
      setState(() => _cart.clear());
      _mostrarNotificacionExito();
      
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.toString());
    }
  }
}