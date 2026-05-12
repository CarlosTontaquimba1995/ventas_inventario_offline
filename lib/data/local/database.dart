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
  RealColumn get precioCompra => real().nullable().named('precio_comp_prod')(); 
  IntColumn get stockLocal => integer().named('stock_total').withDefault(const Constant(0))();
  TextColumn get imagenUrl => text().nullable().named('img_url_prod')(); 
  @override
  Set<Column> get primaryKey => {id};
}

class Ventas extends Table {
  TextColumn get id => text()();
  RealColumn get total => real()();
  DateTimeColumn get fecha => dateTime()(); 
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
  DateTimeColumn get fechaPago => dateTime().nullable()();
  BoolColumn get sincronizado => boolean().withDefault(const Constant(false))();
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
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.addColumn(ventaDetalles, ventaDetalles.fechaPago);
      if (from < 3) {
        await m.addColumn(ventaDetalles, ventaDetalles.sincronizado);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Stream<int> watchConteoPendientes() {
    return (select(ventas)..where((t) => t.sincronizado.equals(false)))
        .watch()
        .map((vList) => vList.length);
  }

  Future<void> registrarVentaCompleta(
    VentasCompanion venta,
    List<VentaDetallesCompanion> detalles,
  ) async {
    await transaction(() async {
      final ahora = DateTime.now();

      await into(ventas).insert(
        venta.copyWith(fecha: Value(ahora), sincronizado: const Value(false)),
      );

      for (var d in detalles) {
        final bool estaPagado = d.pagado.value;

        await into(ventaDetalles).insert(
          d.copyWith(
            fechaPago: estaPagado ? Value(ahora) : const Value.absent(),
            sincronizado: const Value(false),
          ),
        );

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

  Future<void> cobrarProductoFiado(int detalleId) async {
    await transaction(() async {
      final detalle = await (select(
        ventaDetalles,
      )..where((t) => t.id.equals(detalleId))).getSingle();

      await (update(ventaDetalles)..where((t) => t.id.equals(detalleId))).write(
        VentaDetallesCompanion(
          pagado: const Value(true),
          fechaPago: Value(DateTime.now()),
          sincronizado: const Value(false),
        ),
      );

      await (update(ventas)..where((t) => t.id.equals(detalle.ventaId))).write(
        const VentasCompanion(sincronizado: Value(false)),
      );
    });
  }

  Stream<List<Producto>> watchProductosOrdenadosPorVentas() {
    final suma = ventaDetalles.cantidad.sum();
    final q = select(productos).join([
      leftOuterJoin(
        ventaDetalles,
        ventaDetalles.productoId.equalsExp(productos.id),
      )
    ]);
    q
      ..addColumns([suma])
      ..groupBy([productos.id])
      ..orderBy([OrderingTerm(expression: suma, mode: OrderingMode.desc)]);
    return q.watch().map(
      (rows) => rows.map((r) => r.readTable(productos)).toList(),
    );
  }

  Stream<List<ResumenProductoGlobal>> watchResumenGlobalHoy() {
    final inicio = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    final query = select(ventaDetalles).join([
      innerJoin(ventas, ventas.id.equalsExp(ventaDetalles.ventaId)),
      innerJoin(productos, productos.id.equalsExp(ventaDetalles.productoId)),
        ])..where(
          ventas.fecha.isBiggerOrEqualValue(inicio) |
              ventaDetalles.fechaPago.isBiggerOrEqualValue(inicio),
        );

    return query.watch().map((rows) {
      final Map<String, ResumenProductoGlobal> agrupado = {};
      for (final row in rows) {
        final p = row.readTable(productos);
        final d = row.readTable(ventaDetalles);
        final v = row.readTable(ventas);
        final costo = p.precioCompra ?? 0.0;
        final bool esHoy =
            v.fecha.isAfter(inicio) ||
            (d.fechaPago != null && d.fechaPago!.isAfter(inicio));
        double cap = 0, gan = 0, deu = 0;
        if (esHoy) {
          cap = costo * d.cantidad;
          gan = (d.precioUnitario * d.cantidad) - cap;
          deu = d.pagado ? 0.0 : (d.precioUnitario * d.cantidad);
        }
        if (agrupado.containsKey(p.id)) {
          final ex = agrupado[p.id]!;
          agrupado[p.id] = ResumenProductoGlobal(
            nombre: p.nombre,
            cantidadTotal: ex.cantidadTotal + d.cantidad,
            capitalTotal: ex.capitalTotal + cap,
            gananciaTotal: ex.gananciaTotal + gan,
            deudaPendiente: ex.deudaPendiente + deu,
          );
        } else {
          agrupado[p.id] = ResumenProductoGlobal(
            nombre: p.nombre,
            cantidadTotal: d.cantidad,
            capitalTotal: cap,
            gananciaTotal: gan,
            deudaPendiente: deu,
          );
        }
      }
      return agrupado.values.toList();
    });
  }

  Stream<List<VentaConDetalles>> watchVentasDelDiaDetalladas() {
    final inicio = DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    );
    return (select(ventas)
          ..where((t) => t.fecha.isBiggerOrEqualValue(inicio))
          ..orderBy([
            (t) => OrderingTerm(expression: t.fecha, mode: OrderingMode.desc),
          ]))
        .watch()
        .asyncMap((l) async {
          final allP = await select(productos).get();
          final res = <VentaConDetalles>[];
          for (var v in l) {
            final d = await (select(
              ventaDetalles,
            )..where((t) => t.ventaId.equals(v.id))).get();
            res.add(VentaConDetalles(v, d, allP));
      }
          return res;
    });
  }

  Stream<List<VentaConDetalles>> watchCarteraFiadosPendientes() {
    return (select(ventas)..orderBy([
          (t) => OrderingTerm(expression: t.fecha, mode: OrderingMode.desc),
        ]))
        .watch()
        .asyncMap((l) async {
          final allP = await select(productos).get();
          final res = <VentaConDetalles>[];
          for (var v in l) {
            final d =
                await (select(ventaDetalles)..where(
                      (t) => t.ventaId.equals(v.id) & t.pagado.equals(false),
                    ))
                    .get();
            if (d.isNotEmpty) res.add(VentaConDetalles(v, d, allP));
          }
          return res;
        });
  }

  Stream<List<Venta>> watchVentasPendientes() => (select(ventas)..where((t) => t.sincronizado.equals(false))).watch();
  
  Future<void> insertarProductos(List<ProductosCompanion> l) async {
    await batch(
      (b) => b.insertAll(productos, l, mode: InsertMode.insertOrReplace),
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