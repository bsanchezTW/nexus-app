import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:transworld_nexus/data/models/registrado.dart';

void main() {
  final registrado = Registrado(
    id: 'a1b2c3d4-e5f6-7890-abcd-ef1234567890',
    eventoId: 'evento-1',
    nombreCompleto: 'Pedro Soto',
    email: 'pedro@empresa.cl',
    acreditado: true,
    rut: '12.345.678-9',
    patente: 'ABCD12',
    empresa: 'Transworld',
    cargo: 'Jefe de operaciones',
    telefono: '+56 9 8765 4321',
    codigoQr: 'TW1-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    sobrecupo: true,
    origen: OrigenRegistro.excel,
    ingresadoPor: 'perfil-9',
    emailConfirmacionEnviado: true,
    smsConfirmacionEnviado: true,
    createdAt: DateTime.utc(2026, 3, 14, 9, 30),
  );

  group('Registrado.toCacheMap', () {
    // toInsertMap no sirve para la caché: omite id, created_at y
    // los flags de confirmación porque los completa la base de datos.
    test('sobrevive el viaje de ida y vuelta por la caché', () {
      final revivido = Registrado.fromMap(
        Map<String, dynamic>.from(
          jsonDecode(jsonEncode(registrado.toCacheMap())) as Map,
        ),
      );

      expect(revivido.id, registrado.id);
      expect(revivido.eventoId, registrado.eventoId);
      expect(revivido.nombreCompleto, registrado.nombreCompleto);
      expect(revivido.email, registrado.email);
      expect(revivido.acreditado, isTrue);
      expect(revivido.rut, registrado.rut);
      expect(revivido.patente, registrado.patente);
      expect(revivido.empresa, registrado.empresa);
      expect(revivido.cargo, registrado.cargo);
      expect(revivido.telefono, registrado.telefono);
      expect(revivido.codigoQr, registrado.codigoQr);
      expect(revivido.sobrecupo, isTrue);
      expect(revivido.origen, OrigenRegistro.excel);
      expect(revivido.ingresadoPor, registrado.ingresadoPor);
      expect(revivido.emailConfirmacionEnviado, isTrue);
      expect(revivido.smsConfirmacionEnviado, isTrue);
      expect(revivido.createdAt, registrado.createdAt);
      expect(revivido.pendienteDeSincronizar, isFalse);
    });
  });

  group('Registrado.toInsertMap', () {
    test('persiste el origen para RLS e importaciones', () {
      final map = registrado.toInsertMap();

      expect(map['origen'], 'excel');
      expect(map.containsKey('id'), isFalse);
      expect(map.containsKey('created_at'), isFalse);
      expect(map.containsKey('email_confirmacion_enviado'), isFalse);
      expect(map.containsKey('sms_confirmacion_enviado'), isFalse);
    });

    test('incluye origen publico para el formulario anónimo', () {
      const publico = Registrado(
        id: '',
        eventoId: 'evento-1',
        nombreCompleto: 'Ana Díaz',
        email: 'ana@empresa.cl',
        origen: OrigenRegistro.publico,
      );

      expect(publico.toInsertMap()['origen'], 'publico');
    });

    test('normaliza el email a minúsculas', () {
      const conMayusculas = Registrado(
        id: '',
        eventoId: 'evento-1',
        nombreCompleto: 'Ana Díaz',
        email: '  Ana.Diaz@Empresa.CL ',
      );

      expect(conMayusculas.toInsertMap()['email'], 'ana.diaz@empresa.cl');
    });
  });

  group('Registrado.fromMap', () {
    test('lee codigo_qr y sobrecupo', () {
      final desdeMap = Registrado.fromMap({
        'id': 'id-1',
        'evento_id': 'evento-1',
        'nombre_completo': 'Ana Díaz',
        'email': 'ana@empresa.cl',
        'codigo_qr': 'TW1-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB',
        'sobrecupo': true,
      });

      expect(desdeMap.codigoQr, 'TW1-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB');
      expect(desdeMap.sobrecupo, isTrue);
    });

    test('tolera filas sin sms_confirmacion_enviado', () {
      final desdeMap = Registrado.fromMap({
        'id': 'id-1',
        'evento_id': 'evento-1',
        'nombre_completo': 'Ana Díaz',
        'email': 'ana@empresa.cl',
      });

      expect(desdeMap.smsConfirmacionEnviado, isFalse);
      expect(desdeMap.emailConfirmacionEnviado, isFalse);
    });
  });

  group('Registrado.conCambiosPendientes', () {
    test('aplica los campos editados', () {
      final editado = registrado.conCambiosPendientes({
        'nombre_completo': 'Pedro Soto Rivas',
        'cargo': 'Gerente',
      });

      expect(editado.nombreCompleto, 'Pedro Soto Rivas');
      expect(editado.cargo, 'Gerente');
    });

    test('vaciar un campo lo deja en null', () {
      final editado = registrado.conCambiosPendientes({'patente': null});

      expect(editado.patente, isNull);
    });

    test('una columna ausente conserva el valor actual', () {
      final editado = registrado.conCambiosPendientes({'cargo': 'Gerente'});

      expect(editado.rut, registrado.rut);
      expect(editado.patente, registrado.patente);
      expect(editado.empresa, registrado.empresa);
    });

    test('refleja una acreditación encolada', () {
      const sinAcreditar = Registrado(
        id: 'id-1',
        eventoId: 'evento-1',
        nombreCompleto: 'Ana Díaz',
        email: 'ana@empresa.cl',
      );

      final editado = sinAcreditar.conCambiosPendientes({'acreditado': true});

      expect(editado.acreditado, isTrue);
      expect(editado.pendienteDeSincronizar, isTrue);
    });

    test('no pierde el origen ni la fecha de creación', () {
      final editado = registrado.conCambiosPendientes({'cargo': 'Gerente'});

      expect(editado.origen, OrigenRegistro.excel);
      expect(editado.createdAt, registrado.createdAt);
      expect(editado.emailConfirmacionEnviado, isTrue);
      expect(editado.smsConfirmacionEnviado, isTrue);
    });
  });
}
