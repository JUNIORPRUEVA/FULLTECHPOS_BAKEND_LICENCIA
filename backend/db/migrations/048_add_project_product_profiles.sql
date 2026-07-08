-- Rich, editable product documentation for APYRA projects.
-- Commercial settings and license behavior remain untouched.

BEGIN;

ALTER TABLE projects
  ADD COLUMN IF NOT EXISTS product_profile JSONB NOT NULL DEFAULT '{}'::jsonb;

UPDATE projects
SET
  description = 'Gestión móvil y local de clientes, préstamos, cuotas, cobros, contratos y caja.',
  product_profile = $profile$
  {
    "tagline": "Control completo de préstamos desde Android",
    "overview": "FULLCREDIT es una aplicación Android local-first para prestamistas y negocios de crédito. Centraliza clientes, préstamos, calendarios de cuotas, cobros, contratos, caja y reportes en un flujo diseñado para operar rápido desde el teléfono. La información comercial permanece almacenada localmente en el dispositivo.",
    "audience": "Prestamistas independientes, financieras pequeñas, cobradores y negocios que administran crédito directo.",
    "platforms": ["Android"],
    "hero_asset": "assets/projects/fullcredit_logo.png",
    "release_download_url": "",
    "image_1_url": "",
    "image_2_url": "",
    "image_3_url": "",
    "benefits": [
      "Controla la cartera y el balance pendiente desde un solo lugar.",
      "Reduce errores al calcular cuotas, intereses, atrasos y pagos.",
      "Genera contratos, planes de pago y recibos para entregar al cliente.",
      "Funciona con datos locales y permite operar aun cuando no hay internet.",
      "Facilita el seguimiento diario con reportes, caja y clientes en atraso."
    ],
    "requirements": [
      "Teléfono o tableta Android compatible.",
      "Espacio disponible para instalar la aplicación y guardar documentos.",
      "Permiso para instalar el APK cuando se distribuye fuera de Play Store.",
      "Bluetooth activo si se utilizará una impresora térmica.",
      "Internet para activar licencia, comprarla o comprobar actualizaciones."
    ],
    "modules": [
      {"title": "Panel principal", "description": "Resumen de cartera, préstamos activos y saldados, cobros próximos, vencidos y actividad del día.", "icon": "dashboard"},
      {"title": "Clientes", "description": "Registro, edición, contacto, referencias, historial de préstamos y consulta individual.", "icon": "clients"},
      {"title": "Préstamos", "description": "Creación guiada con capital, tasa, plazo, frecuencia, garantías, amortización y calendario de cuotas.", "icon": "loans"},
      {"title": "Simulador", "description": "Calcula escenarios antes de crear el préstamo y permite generar o compartir la simulación.", "icon": "calculator"},
      {"title": "Cobros y pagos", "description": "Aplica pagos a cuotas, distribuye montos, actualiza balances y emite recibos.", "icon": "payments"},
      {"title": "Contratos", "description": "Genera, consulta, imprime y conserva contratos asociados a cada préstamo.", "icon": "contracts"},
      {"title": "Caja", "description": "Apertura, movimientos, aportes, gastos y cierre con comparación entre efectivo declarado y sistema.", "icon": "cash"},
      {"title": "Reportes", "description": "Cartera activa, préstamos saldados, pendiente total, atrasos, vencimientos, pagos y resultados de caja.", "icon": "reports"},
      {"title": "Impresión y WhatsApp", "description": "Impresión térmica Bluetooth, recibos y herramientas de comunicación y soporte.", "icon": "print"},
      {"title": "Licencia y actualización", "description": "Demo, compra en USD, activación automática por PayPal, transferencia asistida y actualización de APK.", "icon": "license"}
    ],
    "installation_steps": [
      "Descarga el APK oficial de FULLCREDIT en el dispositivo Android.",
      "Si Android lo solicita, habilita temporalmente la instalación desde esta fuente.",
      "Abre el APK, confirma Instalar y espera a que termine.",
      "Inicia FULLCREDIT y selecciona demo o activación de licencia.",
      "Completa los datos del negocio, moneda y valores predeterminados de préstamos.",
      "Si imprimirás, empareja la impresora Bluetooth y realiza una prueba.",
      "Crea un cliente y un préstamo de prueba antes de comenzar la operación real."
    ],
    "workflows": [
      {
        "title": "Crear un cliente",
        "description": "Registra la persona antes de asignarle un préstamo.",
        "steps": ["Abre Clientes.", "Pulsa agregar cliente.", "Completa nombre, cédula, teléfono, dirección y referencias.", "Guarda y verifica el detalle del cliente."]
      },
      {
        "title": "Crear un préstamo",
        "description": "Genera el crédito y su calendario de pago.",
        "steps": ["Abre Préstamos y pulsa Nuevo préstamo.", "Selecciona o crea el cliente.", "Define monto, tasa, plazo, frecuencia y fecha del primer pago.", "Revisa el resumen y las cuotas calculadas.", "Confirma y guarda.", "Genera o imprime contrato y plan de pagos cuando corresponda."]
      },
      {
        "title": "Registrar un cobro",
        "description": "Aplica correctamente el dinero recibido.",
        "steps": ["Abre Cobrar o Pagos.", "Busca el cliente o préstamo.", "Selecciona la cuota o distribución correspondiente.", "Indica monto y método de pago.", "Confirma el cobro.", "Imprime o comparte el recibo y verifica el nuevo balance."]
      },
      {
        "title": "Cerrar caja",
        "description": "Comprueba el movimiento del día.",
        "steps": ["Revisa cobros, gastos y aportes registrados.", "Abre Caja y selecciona cerrar.", "Cuenta el efectivo real.", "Ingresa el monto declarado y compara la diferencia.", "Confirma el cierre y conserva el resumen."]
      },
      {
        "title": "Revisar atrasos y reportes",
        "description": "Da seguimiento a la cartera antes de salir a cobrar.",
        "steps": ["Abre Reportes o el panel principal.", "Consulta préstamos vencidos y cuotas próximas.", "Filtra por cliente, fecha o estado.", "Prioriza los clientes con atraso.", "Usa el reporte para planificar llamadas, visitas y cobros del día."]
      },
      {
        "title": "Configurar impresora Bluetooth",
        "description": "Prepara recibos y contratos impresos desde Android.",
        "steps": ["Empareja la impresora desde Android.", "Abre Configuración en FULLCREDIT.", "Selecciona la impresora y el formato de recibo.", "Imprime una prueba.", "Ajusta tamaño o alineación si el recibo sale cortado."]
      },
      {
        "title": "Configurar módulos y comunicación",
        "description": "Deja activa la operación que usará el negocio.",
        "steps": ["Abre Configuración.", "Revisa valores por defecto de préstamos, moneda y caja.", "Activa o desactiva módulos según el negocio.", "Configura WhatsApp o mensajes si se utilizarán recordatorios.", "Guarda y realiza una prueba con un cliente de ejemplo."]
      },
      {
        "title": "Comprar y activar licencia",
        "description": "Activa FULLCREDIT desde la propia aplicación.",
        "steps": ["Abre Licencia y selecciona comprar.", "Elige la cantidad de meses permitida por APYRA.", "Selecciona PayPal o transferencia bancaria disponible para República Dominicana.", "Con PayPal, completa el pago y vuelve a verificar; la licencia se activa automáticamente.", "Con transferencia, continúa por WhatsApp y entrega el comprobante para validación."]
      }
    ],
    "gallery": [
      {"title": "Imagen 1 - Pantalla principal", "asset": "", "caption": "Pega aquí el enlace de la pantalla principal de FULLCREDIT."},
      {"title": "Imagen 2 - Proceso de préstamo", "asset": "", "caption": "Pega aquí el enlace del proceso de préstamo, cuotas o contrato."},
      {"title": "Imagen 3 - Cobros y reportes", "asset": "", "caption": "Pega aquí el enlace de cobros, recibos, caja o reportes."}
    ]
  }
  $profile$::jsonb,
  updated_at = now()
WHERE UPPER(code) = 'FULLCREDIT';

UPDATE projects
SET
  description = 'Sistema de punto de venta para facturación, inventario, caja, clientes, reportes y control interno.',
  product_profile = $profile$
  {
    "tagline": "Punto de venta completo para Windows",
    "overview": "FULLPOS es un sistema de escritorio para administrar la operación comercial de un negocio. Integra ventas y facturación, productos e inventario, clientes, caja, cotizaciones, compras, reportes, usuarios, permisos, impresión y facturación electrónica en una experiencia unificada.",
    "audience": "Tiendas, minimarkets, restaurantes, comercios, distribuidores y empresas que necesitan vender y controlar inventario desde Windows.",
    "platforms": ["Windows"],
    "hero_asset": "assets/projects/fullpos_logo.png",
    "release_download_url": "https://fullpos-backend-fullposlicenciaswed.onqyr1.easypanel.host/api/latest-installer/download",
    "image_1_url": "",
    "image_2_url": "",
    "image_3_url": "",
    "benefits": [
      "Agiliza la facturación con búsqueda, códigos de barras y múltiples tickets.",
      "Mantiene precios, costos, ITBIS, existencias y categorías organizados.",
      "Controla efectivo y otros métodos mediante aperturas, movimientos y cierres de caja.",
      "Protege operaciones sensibles con usuarios, roles y permisos.",
      "Convierte la actividad diaria en reportes de ventas, productos, márgenes y caja."
    ],
    "requirements": [
      "PC con Windows 10 u 11.",
      "Mínimo 2 GB de espacio libre; recomendado 5 GB.",
      "Usuario de Windows con permisos para instalar.",
      "Impresora instalada en Windows si se imprimirán tickets o facturas.",
      "Internet recomendado para licencia, actualizaciones, soporte y funciones en línea."
    ],
    "modules": [
      {"title": "Ventas y facturación", "description": "Tickets múltiples, carrito, cantidades, descuentos, clientes, métodos de pago, impresión y documentos.", "icon": "sales"},
      {"title": "Productos e inventario", "description": "Productos, códigos, categorías, costo, precio, ITBIS, stock, ajustes e importación.", "icon": "inventory"},
      {"title": "Clientes y crédito", "description": "Datos comerciales, contacto, historial de compras y operaciones a crédito.", "icon": "clients"},
      {"title": "Caja", "description": "Apertura, monto inicial, entradas, salidas, aportes, gastos, totales por método y cierre.", "icon": "cash"},
      {"title": "Cotizaciones", "description": "Preparación, consulta y conversión de cotizaciones en ventas.", "icon": "quotes"},
      {"title": "Compras", "description": "Registro y recepción de mercancía para mantener costos y existencias.", "icon": "purchases"},
      {"title": "Devoluciones y anulaciones", "description": "Trazabilidad de correcciones sin borrar el historial comercial.", "icon": "returns"},
      {"title": "Reportes", "description": "Ventas por período, productos, márgenes, caja, usuarios y rendimiento del negocio.", "icon": "reports"},
      {"title": "Usuarios y permisos", "description": "Roles operativos y autorización granular para vender, descontar, anular, editar o consultar.", "icon": "users"},
      {"title": "Facturación electrónica", "description": "Configuración de emisor, secuencias e-CF/eNCF, certificados, diagnóstico y documentos DGII.", "icon": "electronic_invoice"},
      {"title": "Impresión y periféricos", "description": "Tickets, facturas, impresoras, lector de código y apertura de caja registradora.", "icon": "print"},
      {"title": "Respaldo, nube y soporte", "description": "Backups, restauración controlada, diagnóstico, actualización y herramientas de soporte.", "icon": "backup"},
      {"title": "Licencia", "description": "Demo, compra en USD, activación automática por PayPal y transferencia asistida.", "icon": "license"}
    ],
    "installation_steps": [
      "Confirma que la PC utiliza Windows 10/11 y cuenta con espacio disponible.",
      "Descarga la versión oficial de FULLPOS y cierra otras aplicaciones.",
      "Ejecuta el instalador como administrador.",
      "Completa el asistente de instalación y permite la aplicación si Windows o el firewall preguntan.",
      "Abre FULLPOS y activa la demo o licencia.",
      "Configura negocio, RNC, dirección, moneda, usuarios y permisos.",
      "Instala la impresora en Windows, selecciona el formato y realiza una impresión de prueba.",
      "Registra productos y clientes iniciales, abre caja y realiza una venta de prueba.",
      "Configura una rutina de respaldo antes de iniciar la operación real."
    ],
    "workflows": [
      {
        "title": "Crear una factura o venta",
        "description": "Flujo diario principal de FULLPOS.",
        "steps": ["Inicia sesión y abre caja con el monto inicial.", "Abre Ventas y crea o selecciona un ticket.", "Busca o escanea productos y ajusta cantidades.", "Selecciona el cliente si la factura debe llevar sus datos o crédito.", "Aplica descuentos autorizados y revisa impuestos y total.", "Elige efectivo, tarjeta, transferencia u otro método disponible.", "Confirma la venta e imprime o genera la factura."]
      },
      {
        "title": "Registrar un producto",
        "description": "Prepara el catálogo y el inventario.",
        "steps": ["Abre Productos.", "Pulsa nuevo producto.", "Completa nombre, código, categoría, costo, precio e ITBIS.", "Activa el control de stock y registra la existencia inicial cuando aplique.", "Guarda y comprueba que aparezca en Ventas."]
      },
      {
        "title": "Realizar una devolución o anulación",
        "description": "Corrige operaciones conservando trazabilidad.",
        "steps": ["Busca la venta en el historial.", "Selecciona devolución o anulación según el caso.", "Solicita autorización si el usuario no tiene permiso.", "Indica productos, cantidades y motivo.", "Confirma y revisa el ajuste de caja e inventario."]
      },
      {
        "title": "Cerrar caja",
        "description": "Cuadra los valores del turno.",
        "steps": ["Registra todas las entradas y salidas pendientes.", "Abre Caja y revisa totales por método de pago.", "Cuenta el efectivo real.", "Ingresa el monto declarado y valida diferencias.", "Confirma el cierre y guarda o imprime el corte."]
      },
      {
        "title": "Configurar impresora",
        "description": "Deja tickets y facturas listos antes de vender.",
        "steps": ["Conecta la impresora e instala el controlador oficial.", "Imprime una página de prueba desde Windows.", "En FULLPOS abre Configuración e Impresora.", "Selecciona impresora, ancho y formato.", "Realiza una venta de prueba y ajusta tamaño o fuente si es necesario."]
      },
      {
        "title": "Configurar usuarios y permisos",
        "description": "Protege las áreas sensibles antes de entregar el sistema al personal.",
        "steps": ["Abre Usuarios o Configuración.", "Crea usuarios para cajeros, supervisores y administrador.", "Asigna permisos según responsabilidad.", "Prueba iniciar sesión con cada perfil.", "Verifica que anular, descontar o cambiar precios requiera autorización si aplica."]
      },
      {
        "title": "Consultar reportes y respaldar",
        "description": "Convierte la operación diaria en control administrativo.",
        "steps": ["Abre Reportes.", "Selecciona fecha, caja, usuario o producto.", "Revisa ventas, márgenes, productos y movimientos.", "Exporta o imprime cuando sea necesario.", "Ejecuta respaldo según la rutina configurada."]
      },
      {
        "title": "Preparar facturación electrónica",
        "description": "Configura la base necesaria para trabajar con comprobantes electrónicos cuando aplique.",
        "steps": ["Abre el módulo de facturación electrónica.", "Completa datos fiscales del emisor.", "Configura certificado, ambiente y secuencias.", "Ejecuta diagnóstico.", "Realiza una prueba antes de facturar en producción."]
      },
      {
        "title": "Comprar y activar licencia",
        "description": "Activa FULLPOS desde el sistema.",
        "steps": ["Abre Licencia y selecciona comprar.", "Elige los meses disponibles según APYRA.", "Selecciona PayPal o transferencia bancaria para República Dominicana.", "Con PayPal, completa el pago y verifica para activar automáticamente.", "Con transferencia, continúa por WhatsApp y remite el comprobante."]
      }
    ],
    "gallery": [
      {"title": "Imagen 1 - Ventas y facturación", "asset": "", "caption": "Pega aquí el enlace de la pantalla de ventas y facturación."},
      {"title": "Imagen 2 - Productos e inventario", "asset": "", "caption": "Pega aquí el enlace de una imagen del catálogo o inventario."},
      {"title": "Imagen 3 - Caja, reportes y administración", "asset": "", "caption": "Pega aquí el enlace de caja, reportes, usuarios o configuración."}
    ]
  }
  $profile$::jsonb,
  updated_at = now()
WHERE UPPER(code) = 'FULLPOS';

COMMIT;
