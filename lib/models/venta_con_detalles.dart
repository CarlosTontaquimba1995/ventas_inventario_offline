import 'package:ventas_inventario_offline/data/local/database.dart';

class VentaConDetalles {
  final Venta venta;
  final List<String> detallesFormateados;

  VentaConDetalles({
    required this.venta, 
    required this.detallesFormateados
  });
}