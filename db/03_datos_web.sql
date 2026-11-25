-- FEDER Web P2. Configuración inicial de permisos, menú, tarifas y pesos.
-- Requiere 02_datos_dominio.sql. Las cuentas activas comienzan con un marcador
-- sin clave de acceso disponible. Genere una contraseña aleatoria por cuenta
-- desde backend con el comando indicado en el README. Las claves son privadas.

SET client_encoding = 'UTF8';

BEGIN;

SET LOCAL search_path = public;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM usuario WHERE correo = 'administracion@feder.example') THEN
        RAISE EXCEPTION 'Faltan los datos de dominio: cargue antes 02_datos_dominio.sql. No se modificó nada.';
    END IF;
END
$$;

-- -------------------------------------------------------------------------------------
-- 1. Marcar las cuentas de la semilla que aún no recibieron su propia contraseña.
-- -------------------------------------------------------------------------------------
UPDATE usuario
   SET password_hash = '$2y$10$izxxKCHc1MWVIMI9hxCDtubvAmYMA5lTC8DRsN/215suibCoJ6jii'
 WHERE activo
   AND correo LIKE '%@feder.example'
   AND password_hash LIKE 'pbkdf2\_sha256$600000$%' ESCAPE '\';

-- -------------------------------------------------------------------------------------
-- Limpieza de la configuración web anterior (idempotencia)
-- -------------------------------------------------------------------------------------
DELETE FROM confirmacion_operacion
 WHERE usuario_id IS NULL
   AND comando IN ('PERMISO_ROL', 'MENU_WEB', 'TARIFA_ENVIO', 'PESO_PRODUCTO');

-- -------------------------------------------------------------------------------------
-- 2a. Matriz de permisos por rol (VISITANTE = quien no inició sesión)
-- -------------------------------------------------------------------------------------
INSERT INTO confirmacion_operacion (codigo_hash, correo, usuario_id, comando, parametros, expira_en)
SELECT encode(sha256(convert_to('FEDER_WEB:PERMISO_ROL:' || v.rol, 'UTF8')), 'hex'),
       'sistema@feder.example', NULL, 'PERMISO_ROL',
       jsonb_build_object('rol', v.rol, 'permisos', v.permisos),
       '9999-12-31 23:59:59-04'
  FROM (VALUES
    ('VISITANTE', '["inicio.ver", "catalogo.ver"]'::jsonb),
    ('CLIENTE', '["inicio.ver", "catalogo.ver", "perfil.ver", "mi_cuenta.ver", "notificaciones.ver",
                  "carrito.usar", "pedidos.propios", "pagos.propios", "metodos_pago.gestionar",
                  "planes_pago.propios", "facturas.propias", "devoluciones.propias"]'::jsonb),
    ('PRODUCTOR', '["inicio.ver", "catalogo.ver", "perfil.ver", "notificaciones.ver", "productor.panel",
                    "productor.ficha", "producciones.propias", "ventas_feder.propias", "indicadores.propios"]'::jsonb),
    ('PERSONAL_FEDER', '["inicio.ver", "catalogo.ver", "perfil.ver", "notificaciones.ver",
                         "operaciones.panel", "pedidos.gestionar", "pagos.gestionar", "entregas.gestionar",
                         "devoluciones.gestionar", "productos.gestionar", "productores.gestionar",
                         "comunidades.gestionar", "producciones.gestionar", "compras.gestionar",
                         "inventario.ver", "reportes.ver"]'::jsonb),
    -- El administrador puede suplir al personal en toda la operación, más la administración del sistema.
    ('ADMINISTRADOR', '["inicio.ver", "catalogo.ver", "perfil.ver", "notificaciones.ver",
                        "dashboard.ver", "operaciones.panel", "pedidos.gestionar", "pagos.gestionar", "entregas.gestionar",
                        "devoluciones.gestionar", "productos.gestionar", "productores.gestionar",
                        "comunidades.gestionar", "producciones.gestionar", "compras.gestionar",
                        "inventario.ver", "indicadores.ver", "reportes.ver",
                        "administracion.panel", "usuarios.gestionar", "permisos.gestionar", "bitacora.ver", "accesos.ver", "facturas.anular"]'::jsonb)
  ) AS v (rol, permisos);

-- -------------------------------------------------------------------------------------
-- 2b. Menú dinámico: cada entrada se muestra solo si el rol activo tiene su permiso
-- -------------------------------------------------------------------------------------
INSERT INTO confirmacion_operacion (codigo_hash, correo, usuario_id, comando, parametros, expira_en)
SELECT encode(sha256(convert_to('FEDER_WEB:MENU_WEB:' || v.ruta, 'UTF8')), 'hex'),
       'sistema@feder.example', NULL, 'MENU_WEB',
       jsonb_build_object('etiqueta', v.etiqueta, 'ruta', v.ruta, 'permiso', v.permiso,
                          'icono', v.icono, 'grupo', v.grupo, 'orden', v.orden),
       '9999-12-31 23:59:59-04'
  FROM (VALUES
    -- General
    ('Inicio',                '/',                       'inicio.ver',             'inicio',        'General',          10),
    ('Catálogo',              '/catalogo',               'catalogo.ver',           'catalogo',      'General',          20),
    ('Mi perfil',             '/perfil',                 'perfil.ver',             'perfil',        'General',          30),
    ('Notificaciones',        '/notificaciones',         'notificaciones.ver',     'notificaciones','General',          40),
    -- Cliente: el rol CLIENTE tiene su propio espacio «Mi cuenta» (el hub, más las entradas de su flujo)
    ('Mi cuenta',             '/mi-cuenta',              'mi_cuenta.ver',          'cuenta',        'Mi cuenta',       100),
    ('Carrito',               '/carrito',                'carrito.usar',           'carrito',       'Mi cuenta',       110),
    ('Mis pedidos',           '/mis-pedidos',            'pedidos.propios',        'pedidos',       'Mi cuenta',       120),
    ('Mis pagos',             '/mis-pagos',              'pagos.propios',          'pagos',         'Mi cuenta',       130),
    ('Métodos de pago',       '/metodos-pago',           'metodos_pago.gestionar', 'tarjeta',       'Mi cuenta',       140),
    ('Planes de pago',        '/planes-pago',            'planes_pago.propios',    'calendario',    'Mi cuenta',       150),
    ('Mis facturas',          '/mis-facturas',           'facturas.propias',       'factura',       'Mi cuenta',       160),
    ('Mis devoluciones',      '/mis-devoluciones',       'devoluciones.propias',   'devolucion',    'Mi cuenta',       170),
    -- Productor: el hub responde a productor.panel; los demás bloques usan su permiso de dominio
    ('Mi panel productor',    '/productor',              'productor.panel',        'productor',     'Productor',       200),
    ('Mi ficha',              '/productor/ficha',        'productor.ficha',        'ficha',         'Productor',       210),
    ('Mis producciones',      '/productor/producciones', 'producciones.propias',   'brote',         'Productor',       220),
    ('Mis lotes',             '/productor/lotes',        'producciones.propias',   'almacen',       'Productor',       225),
    ('Mis ventas a FEDER',    '/productor/ventas',       'ventas_feder.propias',   'monedas',       'Productor',       230),
    ('Mis propuestas',        '/productor/propuestas',   'producciones.propias',   'envio',         'Productor',       235),
    ('Mis indicadores',       '/productor/indicadores',  'indicadores.propios',    'tendencia',     'Productor',       240),
    -- Operación FEDER (personal y administrador)
    ('Operaciones',           '/operaciones',            'operaciones.panel',      'clavo',         'Operación FEDER', 300),
    ('Panel',                 '/panel',                  'dashboard.ver',          'panel',         'Operación FEDER', 305),
    ('Pedidos',               '/gestion/pedidos',        'pedidos.gestionar',      'portapapeles',  'Operación FEDER', 310),
    ('Pagos',                 '/gestion/pagos',          'pagos.gestionar',        'billetera',     'Operación FEDER', 320),
    ('Entregas',              '/gestion/entregas',       'entregas.gestionar',     'camion',        'Operación FEDER', 330),
    ('Devoluciones',          '/gestion/devoluciones',   'devoluciones.gestionar', 'devolucion',    'Operación FEDER', 340),
    ('Productos',             '/gestion/productos',      'productos.gestionar',    'producto',      'Operación FEDER', 350),
    ('Categorías',            '/gestion/categorias',     'productos.gestionar',    'etiquetas',     'Operación FEDER', 355),
    ('Productores',           '/gestion/productores',    'productores.gestionar',  'tractor',       'Operación FEDER', 360),
    ('Comunidades',           '/gestion/comunidades',    'comunidades.gestionar',  'mapa',          'Operación FEDER', 365),
    ('Producciones y lotes',  '/gestion/producciones',   'producciones.gestionar', 'trigo',         'Operación FEDER', 370),
    ('Compras a productores', '/gestion/compras',        'compras.gestionar',      'bolsa',         'Operación FEDER', 380),
    ('Inventario',            '/gestion/inventario',     'inventario.ver',         'almacen',       'Operación FEDER', 390),
    ('Indicadores',           '/indicadores',            'indicadores.ver',        'grafico',       'Operación FEDER', 395),
    ('Reportes',              '/reportes',               'reportes.ver',           'reporte',       'Operación FEDER', 398),
    -- Administración
    ('Administración',        '/administracion',         'administracion.panel',   'escudo',        'Administración',  400),
    ('Usuarios',              '/admin/usuarios',         'usuarios.gestionar',     'usuarios',      'Administración',  410),
    ('Permisos y menú',       '/admin/permisos',         'permisos.gestionar',     'escudo',        'Administración',  420),
    ('Bitácora',              '/admin/bitacora',         'bitacora.ver',           'bitacora',      'Administración',  430),
    ('Accesos al sitio',      '/admin/accesos',          'accesos.ver',            'actividad',     'Administración',  440)
  ) AS v (etiqueta, ruta, permiso, icono, grupo, orden);

-- -------------------------------------------------------------------------------------
-- 3a. Tarifa de envío (fórmula estilo Yango; valores de ejemplo, editables)
-- -------------------------------------------------------------------------------------
INSERT INTO confirmacion_operacion (codigo_hash, correo, usuario_id, comando, parametros, expira_en)
VALUES (
    encode(sha256(convert_to('FEDER_WEB:TARIFA_ENVIO:VIGENTE', 'UTF8')), 'hex'),
    'sistema@feder.example', NULL, 'TARIFA_ENVIO',
    '{
       "origen": {"nombre": "Almacén FEDER · Plaza 24 de Septiembre", "lat": -17.7833, "lng": -63.1821},
       "cobertura_km": 15,
       "peso_maximo_moto_kg": 20,
       "factor_respaldo_linea_recta": 1.3,
       "vehiculos": {
         "MOTO": {"minimo": 5, "km_incluidos": 1.5, "min_incluidos": 5, "precio_km": 1.00, "precio_min": 0.30},
         "AUTO": {"minimo": 8, "km_incluidos": 1.5, "min_incluidos": 5, "precio_km": 1.50, "precio_min": 0.50}
       },
       "peso_por_unidad_kg": {"KILOGRAMO": 1, "LIBRA": 0.454, "ARROBA": 11.5, "LITRO": 1, "UNIDAD": 0.5}
     }'::jsonb,
    '9999-12-31 23:59:59-04'
);

-- -------------------------------------------------------------------------------------
-- 3b. Peso por unidad de venta de cada producto (kg)
-- -------------------------------------------------------------------------------------
INSERT INTO confirmacion_operacion (codigo_hash, correo, usuario_id, comando, parametros, expira_en)
SELECT encode(sha256(convert_to('FEDER_WEB:PESO_PRODUCTO:' || p.id, 'UTF8')), 'hex'),
       'sistema@feder.example', NULL, 'PESO_PRODUCTO',
       jsonb_build_object('producto_id', p.id, 'peso_kg', v.peso_kg),
       '9999-12-31 23:59:59-04'
  FROM (VALUES
    ('FED-ACE-020', 0.05), ('FED-ACE-100', 0.20), ('FED-JAB-090', 0.09), ('FED-MIE-500', 0.60),
    ('FED-MIE-GRA', 1.00), ('FED-HAR-PLA', 1.00), ('FED-CAF-250', 0.25), ('FED-CAF-GRA', 0.454),
    ('FED-CHO-100', 0.10), ('FED-MER-GUA', 0.35), ('FED-MER-BOS', 0.35),
    ('FED-ACE-PES', 0.20), ('FED-ACE-COP', 0.20), ('FED-ACE-CUS', 0.20), ('FED-ACE-MOT', 0.20),
    ('FED-AES-030', 0.05), ('FED-ALM-CRU', 0.25), ('FED-ALM-TOS', 0.25), ('FED-ALM-SAL', 0.25),
    ('FED-ALM-GRA', 1.00), ('FED-SOY-TOS', 0.25), ('FED-ASA-PUL', 0.50), ('FED-SOY-HAR', 1.00),
    ('FED-CHI-YUC', 0.50), ('FED-DUL-ACH', 0.35), ('FED-CHA-500', 0.50), ('FED-MEL-500', 0.60),
    ('FED-JAB-COP', 0.09), ('FED-JAB-ASA', 0.09), ('FED-CHA-ISO', 0.30), ('FED-ART-ISO', 0.40)
  ) AS v (codigo, peso_kg)
  JOIN producto p ON p.codigo = v.codigo;

COMMIT;
