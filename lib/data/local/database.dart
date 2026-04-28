import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'database.g.dart';
class Productos extends Table {
  TextColumn get id => text()();
  TextColumn get nombre => text()();
  RealColumn get precio => real()();
  IntColumn get stockLocal => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

class Ventas extends Table {
  TextColumn get id => text()();
  RealColumn get total => real()();
  DateTimeColumn get fecha => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get sincronizado => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

class VentaDetalles extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get ventaId => text().references(Ventas, #id)();
  TextColumn get productoId => text().references(Productos, #id)();
  IntColumn get cantidad => integer()();
  RealColumn get precioUnitario => real()();
}

class VentaConDetalles {
  final Venta venta;
  final List<VentaDetalle> detalles;

  VentaConDetalles(this.venta, this.detalles);
  List<String> get detallesFormateados {
    if (detalles.isEmpty) return ["Sin productos"];
    return detalles
        .map((d) => "${d.cantidad}x Producto: ${d.productoId}")
        .toList();
  }
}

@DriftDatabase(tables: [Productos, Ventas, VentaDetalles])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  Stream<List<Producto>> watchProductosOrdenadosPorVentas() {
    final sumaCantidad = ventaDetalles.cantidad.sum();
    final query = select(productos).join([
      leftOuterJoin(
        ventaDetalles,
        ventaDetalles.productoId.equalsExp(productos.id),
      ),
    ]);

    query.addColumns([sumaCantidad]);
    query.groupBy([productos.id]);
    query.orderBy([
      OrderingTerm(expression: sumaCantidad, mode: OrderingMode.desc),
    ]);

    return query.watch().map(
      (rows) => rows.map((row) => row.readTable(productos)).toList(),
    );
  }

  Stream<int> watchVentasPendientesCount() {
    return (select(ventas)..where((t) => t.sincronizado.equals(false)))
        .watch()
        .map((list) => list.length);
  }

  Stream<List<VentaConDetalles>> watchVentasHoyConDetalles() {
    final ahora = DateTime.now();
    final inicioDia = DateTime(ahora.year, ahora.month, ahora.day);
    final streamVentas =
        (select(ventas)
              ..where((t) => t.fecha.isBiggerOrEqualValue(inicioDia))
              ..orderBy([
                (t) =>
                    OrderingTerm(expression: t.fecha, mode: OrderingMode.desc),
              ]))
            .watch();

    return streamVentas.asyncMap((listaVentas) async {
      if (listaVentas.isEmpty) return [];
      final List<String> idsVentas = listaVentas.map((v) => v.id).toList();
      final todosLosDetalles = await (select(
        ventaDetalles,
      )..where((t) => t.ventaId.isIn(idsVentas))).get();
      return listaVentas.map((venta) {
        final detallesDeEstaVenta = todosLosDetalles
            .where((d) => d.ventaId == venta.id)
            .toList();
        return VentaConDetalles(venta, detallesDeEstaVenta);
      }).toList();
    });
  }

  Future<void> registrarVentaCompleta(VentasCompanion venta, List<VentaDetallesCompanion> detalles) async {
    await transaction(() async {
      await into(ventas).insert(venta);
      for (var d in detalles) {
        await into(ventaDetalles).insert(d);
        final p = await (select(
          productos,
        )..where((tbl) => tbl.id.equals(d.productoId.value))).getSingle();
        await (update(
          productos,
        )..where((tbl) => tbl.id.equals(d.productoId.value))).write(
          ProductosCompanion(
            stockLocal: Value(p.stockLocal - d.cantidad.value),
          ),
        );
      }
    });
  }

  Future<void> insertarProductos(List<ProductosCompanion> lista) async {
    await batch(
      (batch) =>
          batch.insertAll(productos, lista, mode: InsertMode.insertOrReplace),
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db_ventas.sqlite'));
    return NativeDatabase(file);
  });
}