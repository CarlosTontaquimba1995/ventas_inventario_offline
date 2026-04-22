import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../local/database.dart';

class SalesRepository {
  final AppDatabase db;
  final _uuid = const Uuid();

  SalesRepository(this.db);

  Future<void> realizarVenta(List<VentaDetallesCompanion> detalles, double total) async {
    return db.transaction(() async {
      final ventaId = _uuid.v4();

      await db.into(db.ventas).insert(VentasCompanion.insert(
        id: ventaId,
        fecha: Value(DateTime.now()),
        total: total,
        sincronizado: const Value(false),
      ));

      for (var detalle in detalles) {
        await db.into(db.ventaDetalles).insert(detalle.copyWith(ventaId: Value(ventaId)));
        final producto = await (db.select(db.productos)
              ..where((p) => p.id.equals(detalle.productoId.value)))
            .getSingle();

        await db.update(db.productos).replace(
          producto.copyWith(stockLocal: producto.stockLocal - detalle.cantidad.value),
        );
      }
    });
  }
}