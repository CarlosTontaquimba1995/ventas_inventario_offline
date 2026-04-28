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
  RealColumn get precioCompra => real().nullable().named('precio_compra')();
  IntColumn get stockLocal =>
      integer().named('stock_total').withDefault(const Constant(0))();
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

class DetalleConCalculo {
  final String nombre;
  final int cantidad;
  final double precioVentaUnitario;
  final double capitalTotalFila;
  final double gananciaTotalFila;

  DetalleConCalculo({
    required this.nombre,
    required this.cantidad,
    required this.precioVentaUnitario,
    required this.capitalTotalFila,
    required this.gananciaTotalFila,
  });
}

class VentaConDetalles {
  final Venta venta;
  final List<VentaDetalle> detallesRaw;
  final List<Producto> productosRelacionados;

  VentaConDetalles(this.venta, this.detallesRaw, this.productosRelacionados);

  List<DetalleConCalculo> get desglosePorProducto {
    return detallesRaw.map((d) {
      final p = productosRelacionados.firstWhere(
        (prod) => prod.id == d.productoId,
        orElse: () => const Producto(
          id: '',
          nombre: 'Desconocido',
          precio: 0,
          stockLocal: 0,
          precioCompra: 0,
        ),
      );

      double costoUnitario = p.precioCompra ?? 0.0;
      double ventaTotalFila = d.precioUnitario * d.cantidad;
      double capitalTotalFila = costoUnitario * d.cantidad;

      return DetalleConCalculo(
        nombre: p.nombre,
        cantidad: d.cantidad,
        precioVentaUnitario: d.precioUnitario,
        capitalTotalFila: capitalTotalFila,
        gananciaTotalFila: ventaTotalFila - capitalTotalFila,
      );
    }).toList();
  }

  double get capitalTotalVenta =>
      desglosePorProducto.fold(0, (sum, item) => sum + item.capitalTotalFila);
  double get gananciaTotalVenta => venta.total - capitalTotalVenta;
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

  Stream<List<VentaConDetalles>> watchVentasDelDiaDetalladas() {
    final ahora = DateTime.now();
    final inicioDia = DateTime(ahora.year, ahora.month, ahora.day);

    return (select(ventas)
          ..where((t) => t.fecha.isBiggerOrEqualValue(inicioDia))
          ..orderBy([
            (t) => OrderingTerm(expression: t.fecha, mode: OrderingMode.desc),
          ]))
        .watch()
        .asyncMap((listaVentas) async {
          final todosLosProductos = await select(productos).get();
          final listaCompleta = <VentaConDetalles>[];

          for (var v in listaVentas) {
            final detalles = await (select(
              ventaDetalles,
            )..where((t) => t.ventaId.equals(v.id))).get();
            listaCompleta.add(VentaConDetalles(v, detalles, todosLosProductos));
          }
          return listaCompleta;
    });
  }

  Stream<List<Venta>> watchVentasPendientes() {
    return (select(ventas)..where((t) => t.sincronizado.equals(false))).watch();
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