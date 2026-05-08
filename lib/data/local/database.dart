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
  IntColumn get stockLocal => integer().named('stock_total').withDefault(const Constant(0))();
  TextColumn get imagenUrl => text().nullable().named('imagen_url')(); 
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
  BoolColumn get pagado => boolean().withDefault(const Constant(true))();
}

class ResumenProductoGlobal {
  final String nombre;
  final int cantidadTotal;
  final double capitalTotal;
  final double gananciaTotal;
  final double deudaPendiente;
  ResumenProductoGlobal({
    required this.nombre,
    required this.cantidadTotal,
    required this.capitalTotal,
    required this.gananciaTotal,
    required this.deudaPendiente,
  });
}

class DetalleConCalculo {
  final int detalleId;
  final String nombre;
  final int cantidad;
  final double precioVentaUnitario;
  final double capitalTotalFila;
  final double gananciaTotalFila;
  final bool fuePagado;

  DetalleConCalculo({
    required this.detalleId,
    required this.nombre,
    required this.cantidad,
    required this.precioVentaUnitario,
    required this.capitalTotalFila,
    required this.gananciaTotalFila,
    required this.fuePagado,
  });
}

class VentaConDetalles {
  final Venta venta;
  final List<VentaDetalle> detallesRaw;
  final List<Producto> productosRelacionados;
  VentaConDetalles(this.venta, this.detallesRaw, this.productosRelacionados);

  List<DetalleConCalculo> get desglosePorProducto {
    return detallesRaw.map((d) {
      final p = productosRelacionados.firstWhere((prod) => prod.id == d.productoId,
        orElse: () => const Producto(
          id: '',
          nombre: 'Desconocido',
          precio: 0,
          stockLocal: 0,
        ),
      );
      double costoUnitario = p.precioCompra ?? 0.0;
      return DetalleConCalculo(
        detalleId: d.id,
        nombre: p.nombre,
        cantidad: d.cantidad,
        precioVentaUnitario: d.precioUnitario,
        capitalTotalFila: costoUnitario * d.cantidad,
        gananciaTotalFila: (d.precioUnitario * d.cantidad) - (costoUnitario * d.cantidad),
        fuePagado: d.pagado,
      );
    }).toList();
  }

  double get efectivoReal => desglosePorProducto
      .where((d) => d.fuePagado)
      .fold(0, (sum, item) => sum + (item.precioVentaUnitario * item.cantidad));
  double get deudaPendiente => venta.total - efectivoReal;
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
    query.orderBy([OrderingTerm(expression: sumaCantidad, mode: OrderingMode.desc)]);
    return query.watch().map((rows) => rows.map((row) => row.readTable(productos)).toList());
  }

  Stream<List<ResumenProductoGlobal>> watchResumenGlobalHoy() {
    final inicioDia = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final query = select(ventaDetalles).join([
      innerJoin(ventas, ventas.id.equalsExp(ventaDetalles.ventaId)),
      innerJoin(productos, productos.id.equalsExp(ventaDetalles.productoId)),
    ])..where(ventas.fecha.isBiggerOrEqualValue(inicioDia));

    return query.watch().map((rows) {
      final Map<String, ResumenProductoGlobal> agrupado = {};
      for (final row in rows) {
        final p = row.readTable(productos);
        final d = row.readTable(ventaDetalles);
        final costoUnitario = p.precioCompra ?? 0.0;
        final capitalFila = costoUnitario * d.cantidad;
        final gananciaFila = (d.precioUnitario * d.cantidad) - capitalFila;
        final deudaFila = d.pagado ? 0.0 : (d.precioUnitario * d.cantidad);

        if (agrupado.containsKey(p.id)) {
          final ex = agrupado[p.id]!;
          agrupado[p.id] = ResumenProductoGlobal(
            nombre: p.nombre,
            cantidadTotal: ex.cantidadTotal + d.cantidad,
            capitalTotal: ex.capitalTotal + capitalFila,
            gananciaTotal: ex.gananciaTotal + gananciaFila,
            deudaPendiente: ex.deudaPendiente + deudaFila,
          );
        } else {
          agrupado[p.id] = ResumenProductoGlobal(
            nombre: p.nombre,
            cantidadTotal: d.cantidad,
            capitalTotal: capitalFila,
            gananciaTotal: gananciaFila,
            deudaPendiente: deudaFila,
          );
        }
      }
      return agrupado.values.toList();
    });
  }

  Stream<List<VentaConDetalles>> watchVentasDelDiaDetalladas() {
    final inicioDia = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    return (select(ventas)..where((t) => t.fecha.isBiggerOrEqualValue(inicioDia))..orderBy([(t) => OrderingTerm(expression: t.fecha, mode: OrderingMode.desc)]))
        .watch().asyncMap((listaVentas) async {
      final todosLosProductos = await select(productos).get();
      final lista = <VentaConDetalles>[];
      for (var v in listaVentas) {
        final detalles = await (select(ventaDetalles)..where((t) => t.ventaId.equals(v.id))).get();
        lista.add(VentaConDetalles(v, detalles, todosLosProductos));
      }
      return lista;
    });
  }

  Stream<List<VentaConDetalles>> watchCarteraFiadosPendientes() {
    return (select(ventas)..orderBy([
          (t) => OrderingTerm(expression: t.fecha, mode: OrderingMode.desc),
        ]))
        .watch()
        .asyncMap((listaVentas) async {
          final todosLosProductos = await select(productos).get();
          final listaConDeudas = <VentaConDetalles>[];
          for (var v in listaVentas) {
            final detallesFiados =
                await (select(ventaDetalles)..where(
                      (t) => t.ventaId.equals(v.id) & t.pagado.equals(false),
                    ))
                    .get();
            if (detallesFiados.isNotEmpty) {
              listaConDeudas.add(
                VentaConDetalles(v, detallesFiados, todosLosProductos),
              );
            }
          }
          return listaConDeudas;
        });
  }

  Future<void> cobrarProductoFiado(int detalleId) async {
    await (update(ventaDetalles)..where((t) => t.id.equals(detalleId))).write(
      const VentaDetallesCompanion(pagado: Value(true)),
    );
  }

  Stream<List<Venta>> watchVentasPendientes() => (select(ventas)..where((t) => t.sincronizado.equals(false))).watch();

  Future<void> registrarVentaCompleta(VentasCompanion venta, List<VentaDetallesCompanion> detalles) async {
    await transaction(() async {
      await into(ventas).insert(venta);
      for (var d in detalles) {
        await into(ventaDetalles).insert(d);
        final p = await (select(productos)..where((tbl) => tbl.id.equals(d.productoId.value))).getSingle();
        await (update(productos)..where((tbl) => tbl.id.equals(d.productoId.value))).write(ProductosCompanion(stockLocal: Value(p.stockLocal - d.cantidad.value)));
      }
    });
  }

  Future<void> insertarProductos(List<ProductosCompanion> lista) async {
    await batch((batch) => batch.insertAll(productos, lista, mode: InsertMode.insertOrReplace));
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'db_ventas.sqlite'));
    return NativeDatabase(file);
  });
}