import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:transworld_nexus/features/home/models/home_featured_item.dart';
import 'package:transworld_nexus/features/home/providers/orden_carrusel_provider.dart';

HomeFeaturedItem _item(String id, {HomeFeaturedKind? kind}) => HomeFeaturedItem(
  kind: kind ?? HomeFeaturedKind.eventoFijado,
  id: id,
  nombre: id,
  fecha: DateTime(2026, 11, 1),
);

List<String> _ids(List<HomeFeaturedItem> items) =>
    items.map((item) => item.id).toList();

void main() {
  test('sin orden guardado queda el orden por defecto', () {
    final items = [_item('a'), _item('b')];
    expect(aplicarOrdenCarrusel(items, const []), items);
  });

  test('respeta el orden que eligió el usuario', () {
    final items = [_item('a'), _item('b'), _item('c')];
    expect(_ids(aplicarOrdenCarrusel(items, ['c', 'a', 'b'])), ['c', 'a', 'b']);
  });

  test('una tarjeta nueva entra en su lugar por defecto', () {
    // El usuario ordenó b, a; después apareció la próxima actividad (p),
    // que por defecto va al final.
    final items = [
      _item('a'),
      _item('b'),
      _item('p', kind: HomeFeaturedKind.proximaActividad),
    ];
    expect(_ids(aplicarOrdenCarrusel(items, ['b', 'a'])), ['b', 'a', 'p']);
  });

  test('lo que ya no está en el carrusel no deja huecos', () {
    final items = [_item('a'), _item('c')];
    expect(_ids(aplicarOrdenCarrusel(items, ['c', 'b', 'a'])), ['c', 'a']);
  });

  test('el orden se guarda por cuenta en el teléfono', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final mio = OrdenCarrusel(prefs, 'usuario-a');
    await mio.guardar([_item('b'), _item('a')]);

    expect(OrdenCarrusel(prefs, 'usuario-a').state, ['b', 'a']);
    expect(OrdenCarrusel(prefs, 'usuario-b').state, isEmpty);

    await mio.restablecer();
    expect(OrdenCarrusel(prefs, 'usuario-a').state, isEmpty);
  });
}
