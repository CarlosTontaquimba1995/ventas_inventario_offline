import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:ventas_inventario_offline/models/venta_con_detalles.dart';

part 'database.g.dart';

class Productos extends Table {
  TextColumn get id => text()();
  TextColumn get nombre => text()();
  RealColumn get precio => real()();
  IntColumn get stockLocal => integer().withDefault(const Constant(0))();
  DateTimeColumn get actualizadoAt => dateTime().nullable()(); 
  @override
  Set<Column> get primaryKey => {id};
}

class Ventas extends Table {
  TextColumn get id => text()();
  DateTimeColumn get fecha => dateTime().withDefault(currentDateAndTime)();
  RealColumn get total => real()();
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

@DriftDatabase(tables: [Productos, Ventas, VentaDetalles])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  Stream<int> watchVentasPendientesCount() {
    return (select(ventas)..where((t) => t.sincronizado.equals(false)))
        .watch()
        .map((list) => list.length);
  }

  Future<void> insertarProductos(List<ProductosCompanion> lista) async {
    await batch((b) {
      b.insertAll(productos, lista, mode: InsertMode.insertOrReplace);
    });
  }

  Stream<List<VentaConDetalles>> watchVentasHoyConDetalles() {
    final hoy = DateTime.now();
    final inicioDia = DateTime(hoy.year, hoy.month, hoy.day);

    final queryVentas = select(ventas)
      ..where((t) => t.fecha.isBiggerOrEqualValue(inicioDia))
      ..orderBy([(t) => OrderingTerm.desc(t.fecha)]);

    return queryVentas.watch().asyncMap((listadoVentas) async {
      final List<VentaConDetalles> resultado = [];
      for (var venta in listadoVentas) {
        final queryJoin = select(ventaDetalles).join([
          innerJoin(productos, productos.id.equalsExp(ventaDetalles.productoId)),
        ])..where(ventaDetalles.ventaId.equals(venta.id));

        final filas = await queryJoin.get();
        final detallesTexto = filas.map((row) {
          final d = row.readTable(ventaDetalles);
          final p = row.readTable(productos);
          return '${d.cantidad}x ${p.nombre}';
        }).toList();

        resultado.add(VentaConDetalles(venta: venta, detallesFormateados: detallesTexto));
      }
      return resultado;
    });
  }

  Future<void> registrarVentaCompleta(VentasCompanion venta, List<VentaDetallesCompanion> detalles) async {
    await transaction(() async {
      await into(ventas).insert(venta);
      for (var d in detalles) {
        await into(ventaDetalles).insert(d);
        final producto = await (select(productos)..where((p) => p.id.equals(d.productoId.value))).getSingle();
        await (update(productos)..where((p) => p.id.equals(d.productoId.value)))
            .write(ProductosCompanion(stockLocal: Value(producto.stockLocal - d.cantidad.value)));
      }
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'tienda_v3.sqlite'));
    return NativeDatabase(file);
  });
}