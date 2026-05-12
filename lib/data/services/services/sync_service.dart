import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:drift/drift.dart' as d;
import 'package:ventas_inventario_offline/data/local/database.dart';

class SyncService {
  final AppDatabase db;
  final supabase = Supabase.instance.client;

  SyncService(this.db);

  Future<void> sincronizacionCompletaSegura() async {
    try {
      final ventasPendientes = await (db.select(
        db.ventas,
      )..where((t) => t.sincronizado.equals(false))).get();

      for (var venta in ventasPendientes) {
        final detalles = await (db.select(
          db.ventaDetalles,
        )..where((t) => t.ventaId.equals(venta.id))).get();

        await supabase.from('ventas').upsert({
          'id': venta.id,
          'fecha': venta.fecha.toLocal().toIso8601String(),
          'total': venta.total,
        });

        final detallesJson = detalles
            .map(
              (det) => {
                'venta_id': det.ventaId,
                'producto_id': det.productoId,
                'cantidad': det.cantidad,
                'precio_unitario': det.precioUnitario,
                'pagado': det.pagado,
                'fecha_pago': det.fechaPago?.toLocal().toIso8601String(),
              },
            )
            .toList();

        await supabase
            .from('venta_detalles')
            .upsert(detallesJson, onConflict: 'venta_id, producto_id');

        await (db.update(db.ventas)..where((t) => t.id.equals(venta.id))).write(
          const VentasCompanion(sincronizado: d.Value(true)),
        );

        await (db.update(db.ventaDetalles)
              ..where((t) => t.ventaId.equals(venta.id)))
            .write(const VentaDetallesCompanion(sincronizado: d.Value(true)));
      }

      await descargarCatalogoDesdeNube();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> descargarCatalogoDesdeNube() async {
    final response = await supabase.from('productos').select();
    final productosNube = (response as List)
        .map(
          (p) => ProductosCompanion(
            id: d.Value(p['id']),
            nombre: d.Value(p['nombre']),
            precio: d.Value((p['precio'] as num).toDouble()),
            precioCompra: d.Value(
              (p['precio_compra'] as num?)?.toDouble() ?? 0.0,
            ),
            stockLocal: d.Value((p['stock_total'] as num?)?.toInt() ?? 0),
            imagenUrl: d.Value(p['imagen_url'] as String?),
          ),
        )
        .toList();

    await db.batch(
      (batch) => batch.insertAll(
        db.productos,
        productosNube,
        mode: d.InsertMode.insertOrReplace,
      ),
    );
  }
}