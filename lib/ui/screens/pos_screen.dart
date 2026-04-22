import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' as d hide Column;
import '../../data/local/database.dart';
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

  void _mostrarNotificacionExito() {
    setState(() {
      _showSuccessMessage = true;
      _errorMessage = null;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showSuccessMessage = false);
      }
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
            icon: const Icon(Icons.analytics, size: 30),
            onPressed: () => Navigator.push(
              context, 
              MaterialPageRoute(builder: (c) => const DailySummaryScreen())
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
                      ? db.select(db.productos).watch() 
                      : (db.select(db.productos)..where((p) => p.nombre.lower().contains(_searchQuery.toLowerCase()))).watch(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      final productos = snapshot.data!;
                      if (productos.isEmpty) return const Center(child: Text('No hay productos.'));

                      return GridView.builder(
                        padding: const EdgeInsets.all(10),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3, 
                          childAspectRatio: 0.85,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10
                        ),
                        itemCount: productos.length,
                        itemBuilder: (context, i) {
                          final p = productos[i];
                          final bool hasStock = p.stockLocal > 0;
                          return Card(
                            elevation: 3,
                            color: hasStock ? Colors.white : Colors.grey[200],
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            child: InkWell(
                              onTap: hasStock ? () => setState(() => _cart.add(p)) : null,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(p.nombre, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                                  Text('\$${p.precio.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, color: Colors.green, fontWeight: FontWeight.bold)),
                                  Text('Stock: ${p.stockLocal}', style: TextStyle(color: hasStock ? Colors.blue : Colors.red)),
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
          
          Container(
            width: 350,
            decoration: BoxDecoration(
              color: Colors.blueGrey[50],
              border: Border(left: BorderSide(color: Colors.grey.shade300))
            ),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20), 
                  child: Text('DETALLE DE VENTA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _cart.length,
                    itemBuilder: (context, i) => ListTile(
                      title: Text(_cart[i].nombre),
                      subtitle: Text('\$${_cart[i].precio.toStringAsFixed(2)}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red), 
                        onPressed: () => setState(() => _cart.removeAt(i))
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
                            '\$${_cart.fold(0.0, (s, item) => s + item.precio).toStringAsFixed(2)}', 
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green)
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity, 
                        height: 60, 
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green, 
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                          ),
                          onPressed: _cart.isEmpty ? null : () => _finalizarVenta(context),
                          child: const Text('COBRAR', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        )
                      ),
                    ],
                  ),
                )
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
      curve: Curves.easeOut,
      height: (_showSuccessMessage || _errorMessage != null) ? 60 : 0,
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: _showSuccessMessage ? Colors.green : Colors.red,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 5)],
      ),
      child: FadeInWidget(
        visible: _showSuccessMessage || _errorMessage != null,
        child: Row(
          children: [
            Icon(
              _showSuccessMessage ? Icons.check_circle : Icons.error, 
              color: Colors.white
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                _showSuccessMessage ? '¡Venta Exitosa!' : (_errorMessage ?? ''),
                style: const TextStyle(
                  color: Colors.white, 
                  fontSize: 16, 
                  fontWeight: FontWeight.bold
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _finalizarVenta(BuildContext context) async {
    final db = Provider.of<AppDatabase>(context, listen: false);
    
    final String ventaId = DateTime.now().millisecondsSinceEpoch.toString();
    final double totalVenta = _cart.fold(0.0, (s, item) => s + item.precio);
    final nuevaVenta = VentasCompanion.insert(
      id: ventaId, total: totalVenta, fecha: d.Value(DateTime.now()), sincronizado: const d.Value(false),
    );
    final Map<String, int> agrupados = {};
    for (var p in _cart) { agrupados[p.id] = (agrupados[p.id] ?? 0) + 1; }
    final detalles = agrupados.entries.map((e) {
      final p = _cart.firstWhere((x) => x.id == e.key);
      return VentaDetallesCompanion.insert(
        ventaId: ventaId, productoId: e.key, cantidad: e.value, precioUnitario: p.precio
      );
    }).toList();

    try {
      await db.registrarVentaCompleta(nuevaVenta, detalles);
      
      if (!context.mounted) return;

      setState(() {
        _cart.clear();
      });

      _mostrarNotificacionExito();

    } catch (e) {
      if (!context.mounted) return;
      setState(() => _errorMessage = 'Error: $e');
    }
  }
}

class FadeInWidget extends StatelessWidget {
  final bool visible;
  final Widget child;

  const FadeInWidget({super.key, required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: visible ? 1.0 : 0.0,
      child: visible ? child : const SizedBox.shrink(),
    );
  }
}