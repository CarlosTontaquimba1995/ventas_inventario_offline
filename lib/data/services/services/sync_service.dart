import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:drift/drift.dart' as d;
import 'package:ventas_inventario_offline/data/local/database.dart';

class SyncService {
  final AppDatabase db;
  final supabase = Supabase.instance.client;

  SyncService(this.db);

  Future<void> descargarCatalogoDesdeNube() async {
    try {
      final response = await supabase.from('productos').select();
      final List<ProductosCompanion> productosNube = (response as List).map((
        p,
      ) {
        return ProductosCompanion.insert(
          id: p['id'],
          nombre: p['nombre'],
          precio: (p['precio'] as num).toDouble(),
          stockLocal: d.Value((p['stock_total'] as num).toInt()), 
        );
      }).toList();

      await db.batch((batch) {
        batch.insertAll(
          db.productos,
          productosNube,
          mode: d.InsertMode.insertOrReplace,
        );
      });
    } catch (e) {
      rethrow;
    }
  }

  Future<void> sincronizacionCompletaSegura() async {
    try {
      final ventasPendientes = await (db.select(
        db.ventas,
      )..where((tbl) => tbl.sincronizado.equals(false))).get();

      if (ventasPendientes.isNotEmpty) {
        await sincronizarVentas();
      }
      await descargarCatalogoDesdeNube();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> sincronizarVentas() async {
    final ventasPendientes = await (db.select(
      db.ventas,
    )..where((t) => t.sincronizado.equals(false))).get();

    for (var venta in ventasPendientes) {
      final detalles = await (db.select(
        db.ventaDetalles,
      )..where((t) => t.ventaId.equals(venta.id))).get();
      await supabase.from('ventas').insert({
        'id': venta.id,
        'fecha': venta.fecha.toIso8601String(),
        'total': venta.total,
      });

      final detallesJson = detalles
          .map(
            (d) => {
              'venta_id': d.ventaId,
              'producto_id': d.productoId,
              'cantidad': d.cantidad,
              'precio_unitario': d.precioUnitario,
            },
          )
          .toList();

      await supabase.from('venta_detalles').insert(detallesJson);

      await (db.update(db.ventas)..where((t) => t.id.equals(venta.id)))
        .write(
        const VentasCompanion(sincronizado: d.Value(true)),
      );
    }
  }
}