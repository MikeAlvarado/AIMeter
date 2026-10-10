import type { Dictionary } from './types'

export const es = {
  meta: {
    title: 'AIMeter — Tus límites de IA, de un vistazo',
    description:
      'AIMeter te dice cuánto te queda de tu suscripción de IA: límites por sesión, semana y modelo en widgets, en la pantalla de bloqueo y en la barra de menús del Mac. Gratis, open source, sin servidor.',
  },
  nav: {
    features: 'Funciones',
    widgets: 'Widgets',
    privacy: 'Privacidad',
    openSource: 'Open source',
    support: 'Soporte',
    cta: 'Descargar',
    openMenu: 'Abrir menú',
    closeMenu: 'Cerrar menú',
    langLabel: 'Idioma',
    navLabel: 'Navegación principal',
    home: 'Inicio de AIMeter',
  },
  hero: {
    pills: ['Gratis', 'Open source', 'Sin cuenta'],
    line1: 'Sabe cuánto te queda',
    line2: '*antes* de toparte con la pared.',
    sub: 'AIMeter muestra los límites de tu suscripción de IA por sesión, semana y modelo donde ya miras: widgets, pantalla de bloqueo y la barra de menús del Mac.',
    appStore: 'Descárgala en el App Store',
    appStoreSmall: 'Descárgala en el',
    github: 'Ver en GitHub',
    scroll: 'Desliza para explorar',
    platforms: 'iPhone · iPad · Mac',
    version: 'Versión',
    phoneAlt: 'Panel de AIMeter en iPhone: dos cuentas, cada una con límites de sesión, semana y modelo como barras con cuenta regresiva.',
    widgetAlt: 'Widget mediano con dos columnas: Sesión 42 % restante y Semana 11 % restante, cada una con su barra y hora de reinicio.',
  },
  statement:
    'Cada límite por el que pagas, en un solo lugar. Sin servidor, sin cuenta, sin analíticas. De tu dispositivo no sale nada más que la petición que lee tu propio uso.',
  features: {
    heading: 'Lo que *hace*',
    sub: 'Todo lo que muestra la app viene directo de los números de tu proveedor.',
    listLabel: 'Funciones',
    items: [
      {
        id: 'limits',
        title: 'Todos tus límites, de un vistazo',
        body: 'Ventanas de sesión, semana y modelo para cada cuenta que conectes, cada una con su barra, el porcentaje exacto y la cuenta regresiva a su reinicio.',
        points: ['Restante o usado, tú eliges', 'Reinicios relativos o absolutos', 'Plan y topes de gasto, tal como los reporta el proveedor'],
        imageAlt: 'Panel con dos cuentas y sus barras de límites.',
      },
      {
        id: 'widgets',
        title: 'Widgets que llevan la cuenta',
        body: 'Widgets chico, mediano y grande en la pantalla de inicio, accesorios de pantalla de bloqueo y un widget de una sola cifra para el límite que te importa. En iOS se actualizan solos en segundo plano.',
        points: ['Una cuenta o todas', 'Medidor en la pantalla de bloqueo con tu métrica', 'Botón de actualizar en el propio widget'],
        imageAlt: 'Pantalla de inicio con los widgets chico, mediano y grande de AIMeter.',
      },
      {
        id: 'history',
        title: 'Cada reinicio, graficado',
        body: 'Una gráfica de historial por cuenta: el porcentaje usado de cada límite en el último día, semana o mes, con cada reinicio marcado, a partir de muestras guardadas en tu dispositivo por 30 días.',
        points: ['24 horas, 7 días o 30 días', 'Una minigráfica por fila en el panel', 'Resumen hablado para VoiceOver'],
        imageAlt: 'Gráfica del uso semanal en 30 días con marcas de reinicio.',
      },
      {
        id: 'alerts',
        title: 'Alertas antes de la pared',
        body: 'Notificaciones locales, por cuenta: cerca de un límite, proyección de agotarse antes de tiempo, límite alcanzado, reinicio anticipado, y la única que viene activada: cuando un inicio de sesión deja de funcionar.',
        points: ['Tu propio umbral de alerta', 'Recordatorios de reinicio por ventana', 'Generadas en el dispositivo, sin servicio push'],
        imageAlt: 'Interruptores de notificaciones de una cuenta.',
      },
      {
        id: 'pace',
        title: 'Conoce tu ritmo',
        body: 'Cada ventana te dice si vas al ritmo, adelantado o atrasado respecto a un consumo parejo hasta el siguiente reinicio, y una tarjeta de Pronóstico proyecta cuáles se agotarán antes.',
        points: ['Aprende tu ritmo antes de afirmarlo', 'Proyección promedio y de ritmo reciente', 'Nada se inventa a partir de datos faltantes'],
        imageAlt: 'Detalle de cuenta con el ritmo por fila y la tarjeta de Pronóstico.',
      },
      {
        id: 'accounts',
        title: 'Cada cuenta, su propio ícono',
        body: 'Conecta tantas cuentas como quieras. Cada una lleva un nombre y un ícono a tu gusto, visibles en el panel, en la barra de menús, en cada widget y en la Live Activity. Modo oscuro incluido.',
        points: ['Arrastra para reordenar, en todas partes a la vez', 'Renombra o cambia el ícono cuando quieras', '“Iniciar sesión de nuevo” repara la cuenta en su lugar'],
        imageAlt: 'Panel en modo oscuro con dos cuentas e íconos personalizados.',
      },
    ],
  },
  widgets: {
    heading: 'Widgets *donde quiera* que mires',
    sub: 'Tres tipos de widget, la pantalla de bloqueo y una Live Activity, todos dibujados del mismo registro que guarda la app.',
    kinds: [
      { title: 'Usage Limits', body: 'Una cuenta. Filas en el tamaño chico; columnas lado a lado con cifra grande en el mediano.' },
      { title: 'Single Limit', body: 'Una sola cifra: eliges la cuenta y la ventana desde la configuración del propio widget.' },
      { title: 'All Accounts', body: 'Todas las cuentas conectadas a la vez, en el tamaño grande.' },
    ],
    homeAlt: 'Pantalla de inicio del iPhone con los tres tipos de widget de AIMeter.',
    lockScreen: 'Pantalla de bloqueo',
    liveActivity: 'Live Activity',
    liveActivityBody: 'Actívala por cuenta para tener la cuenta regresiva de la sesión en la pantalla de bloqueo y en la Dynamic Island mientras corre. El reloj avanza en el dispositivo; el porcentaje se actualiza cada vez que la app o un widget vuelve a consultar.',
    ipadAlt: 'AIMeter en iPad.',
  },
  mac: {
    heading: 'En el Mac vive en el *notch*',
    sub: 'Una isla negra fundida al notch de la MacBook muestra todas las ventanas en una línea: asoma tus cifras cuando el cursor se detiene encima y abre todas las cuentas si te quedas o haces clic, sin robar el foco nunca. ¿Sin notch? Una pastilla flotante bajo la barra de menús. ¿Prefieres un ícono de estado? Seis estilos, alimentados por la propia app, para que los widgets del Centro de notificaciones sigan frescos sin ningún ícono en pantalla.',
    styles: ['Medidor con el número', 'Solo medidor', 'Solo número', 'Barra', 'Batería', 'Dos o tres ventanas lado a lado'],
    extras: [
      'Isla del notch: 5h 42% 2h 58m | 7d 61% 3d 3h junto al notch, y todas las cuentas con barras y reinicios al abrirse',
      'Elige de qué lado del notch van las alas y qué ventanas listan; activarla oculta el ícono de la barra',
      'Cuenta regresiva al reinicio y nombre de la cuenta, opcionales',
      'En rojo cuando una ventana pasa del 80 %',
      'Oculta el ícono del Dock, el de la barra, o ambos',
      'Abrir al iniciar sesión, opcional y siempre visible en Ajustes',
      '⌘R actualizar, ⌘N agregar cuenta, y dos acciones de Atajos que puedes ligar a cualquier tecla',
    ],
    note: 'La app de Mac no está en la Mac App Store: lee el inicio de sesión que ya guardan tus herramientas de línea de comandos, y el sandbox de la tienda no lo permite.',
    build: 'Compílala desde el código',
    islandAlt: 'La isla del notch en una MacBook, en tres estados: el notch a secas; dos cifras a sus lados cuando el cursor se detiene encima; y, expandida, dos cuentas con cada ventana, su barra y el tiempo hasta su reinicio.',
    islandStates: ['Cerrada: el notch, nada encima', 'Detén el cursor encima: tus cifras junto al notch', 'Quédate un segundo, o haz clic: todas las cuentas'],
  },
  privacy: {
    heading: 'Privada *por diseño*',
    sub: 'Lo bastante pequeña para leerla. Cada afirmación de aquí se puede verificar en el código.',
    points: [
      { title: 'Sin servidor, sin cuenta', body: 'El uso se lee directo de tu proveedor y se guarda en tu dispositivo para que los widgets lo muestren. AIMeter no pone nada propio en medio.' },
      { title: 'Los tokens viven en el llavero', body: 'Tu token de inicio de sesión lo guarda cifrado el sistema y se usa para una sola cosa: leer tu uso. AIMeter pide un permiso de solo lectura y nunca uno que pueda ejecutar prompts.' },
      { title: 'Sin analíticas, sin rastreo', body: 'Sin SDK de analíticas, sin redes de anuncios, sin reportes de fallos. Este sitio también es estático y no hace peticiones a terceros.' },
      { title: 'Tuyo para borrarlo', body: 'Desconectar una cuenta borra su token, su registro guardado y su historial. No queda nada en la nube, porque nunca hubo nada ahí.' },
    ],
    cta: 'Lee la política de privacidad',
  },
  openSource: {
    heading: 'Open source, *gratis para siempre*',
    sub: 'Licencia MIT. Sin planes, sin suscripción, sin funciones bloqueadas. Lo que otros trackers cobran, aquí simplemente está.',
    points: [
      { title: 'Audítala tú mismo', body: 'El repo incluye scripts que imprimen el JSON exacto que la app lee con tu propio inicio de sesión. El token nunca se imprime ni se escribe en disco.' },
      { title: 'Compila la app de Mac', body: 'Clona, pon tu Team ID en un archivo ignorado por git y compila. Con una cuenta de desarrollador gratuita basta para tus propios equipos.' },
      { title: 'SwiftUI puro', body: 'iOS 17+ y macOS 14+, sin dependencias, un paquete Swift agnóstico del proveedor. Más proveedores pueden entrar como secciones nuevas.' },
    ],
    languagesLabel: 'Disponible en',
    languages: 'inglés, español, alemán, francés, japonés, coreano, portugués de Brasil y chino simplificado',
    github: 'Dale una estrella en GitHub',
  },
  closing: {
    eyebrow: 'Gratis en el App Store para iPhone y iPad. Compílala tú para el Mac.',
    heading: 'Tus límites, *en tus términos*.',
    appStore: 'Descárgala en el App Store',
    github: 'Ver el código',
    rights: 'Licencia MIT.',
    trademark:
      'AIMeter es un proyecto open source independiente. No está afiliado, avalado ni patrocinado por ningún proveedor de IA; los nombres de productos son marcas de sus respectivos dueños.',
    madeBy: 'Hecho por',
    links: { privacy: 'Privacidad', support: 'Soporte', source: 'Código' },
  },
  privacyPage: {
    title: 'Política de privacidad',
    description: 'Qué lee AIMeter, qué guarda en tu dispositivo y qué nunca sale de él.',
    intro:
      'AIMeter no tiene servidor ni cuenta propia. Lee tu uso de tu proveedor de IA con el inicio de sesión que le concedes, guarda una copia en tu dispositivo para que los widgets puedan dibujarla y no envía nada a ningún otro lado. Esta página enumera cada flujo de datos para que puedas cotejarlo con el código fuente.',
    updated: 'Última actualización: 7 de octubre de 2026',
    sections: [
      {
        heading: 'Qué sale de tu dispositivo',
        paragraphs: ['Solo peticiones HTTPS al proveedor cuyo uso le pediste a AIMeter que lea, y nada hacia nosotros, porque no hay un “nosotros” al que enviarlo.'],
        bullets: [
          'api.anthropic.com — /api/oauth/usage para tus límites y cifras de gasto, y /api/oauth/profile para resolver el nombre de tu plan (se vuelve a consultar como máximo cada 6 horas).',
          'claude.ai y console.anthropic.com — el intercambio OAuth estándar al conectar una cuenta desde la app. Inicias sesión en la página del propio proveedor en tu navegador, nunca en una vista web incrustada, y pegas de vuelta el código que te muestra.',
          'status.claude.com — una petición anónima a la página pública de estado en cada actualización, para distinguir un incidente del servicio de un problema con tu cuenta. No lleva nada sobre ti y se puede apagar en Ajustes.',
          'Este sitio es estático: sin analíticas, sin cookies, con tipografías alojadas aquí mismo y sin peticiones a terceros. Lo sirve GitHub Pages, cuyos registros ordinarios de servidor son de GitHub.',
        ],
      },
      {
        heading: 'Qué se guarda, y dónde',
        paragraphs: ['Todo lo siguiente vive en el dispositivo, en almacenamiento que solo AIMeter y su widget pueden leer.'],
        bullets: [
          'Tokens de inicio de sesión: únicamente en el llavero del sistema, cifrados, disponibles tras el primer desbloqueo. En iOS el widget los comparte a través del grupo de acceso al llavero del App Group para poder actualizar el uso por su cuenta. En el Mac, una primera cuenta puede simplemente leer el inicio de sesión que ya guarda tu herramienta de línea de comandos, en solo lectura y sin modificarlo jamás.',
          'El último registro de uso (porcentajes, fechas de reinicio, cifras de gasto) y tus preferencias de visualización: en el contenedor del App Group, para que los widgets dibujen sin consultar la red.',
          'Hasta 30 días de porcentajes de uso por ventana (las cifras, sus fechas y las fechas de reinicio), como un archivo pequeño por cuenta en el mismo contenedor, para la gráfica de historial.',
          'Nunca se escribe nada en otro lugar del dispositivo, sin cifrar, ni fuera de los contenedores de la propia app.',
        ],
      },
      {
        heading: 'A qué puede acceder la conexión',
        paragraphs: [
          'Cuando inicias sesión a través de AIMeter, pide un único permiso OAuth, user:profile, que es el que necesitan los endpoints de uso y de perfil. Nunca pide el permiso de inferencia, así que un token emitido para AIMeter no puede enviar prompts ni gastar uso en tu nombre, ni siquiera en teoría. La app solo llama a dos endpoints de solo lectura: tus ventanas de uso y tu perfil.',
        ],
      },
      {
        heading: 'Registros de la línea de comandos (Mac, opcional)',
        paragraphs: [
          'Apagado por defecto. Si activas “Leer los registros locales de uso de Claude Code” en Ajustes, AIMeter lee los registros de sesión que esa herramienta guarda en ~/.claude/projects en ese Mac para sumar tokens por modelo y valorarlos a precios públicos de lista. Decodifica solo los campos de uso de cada registro, nunca prompts ni respuestas; guarda un índice pequeño de conteos en su propia carpeta de Application Support; borra ese índice al apagar la opción; y no envía nada a ningún lado. La función no existe en iOS.',
        ],
      },
      {
        heading: 'Notificaciones',
        paragraphs: [
          'Todas las alertas se generan localmente en el dispositivo a partir de las fechas de reinicio y los porcentajes que ya están en el registro. No interviene ningún servicio push, y nada se entrega si no concediste el permiso de notificaciones.',
        ],
      },
      {
        heading: 'Abrir al iniciar sesión (Mac, opcional)',
        paragraphs: [
          'AIMeter nunca se agrega sola a tus elementos de inicio. Activar “Abrir al iniciar sesión” en Ajustes la registra en macOS, que te pide aprobarlo; apagarla elimina el registro. Lo único que hace al arrancar es leer tu uso.',
        ],
      },
      {
        heading: 'Borrar tus datos',
        paragraphs: [
          'Desconectar una cuenta desde su pantalla de detalle borra su token guardado, su registro, su historial y sus preferencias de notificaciones. Borrar la app elimina sus contenedores; desconecta primero si quieres asegurarte de que no quede ningún elemento en el llavero. No hay nada que borrar en ningún servidor.',
        ],
      },
      {
        heading: 'Menores',
        paragraphs: ['AIMeter no está dirigida a menores de 13 años y, como se describe arriba, no recopila datos personales de nadie.'],
      },
      {
        heading: 'Cambios',
        paragraphs: [
          'Los cambios a esta política se publican en esta página con una fecha nueva. El historial completo de la página, igual que el de la app, está en el repositorio público.',
        ],
      },
      {
        heading: 'Contacto y marcas',
        paragraphs: [
          'Las dudas van a la página de soporte. AIMeter es un proyecto open source independiente (MIT). No está afiliado, avalado ni patrocinado por Anthropic. “Claude” y “Anthropic” son marcas de Anthropic, PBC, usadas únicamente para identificar el servicio cuyo uso muestra la app.',
        ],
      },
    ],
  },
  supportPage: {
    title: 'Soporte',
    description: 'Cómo conectar una cuenta, qué significan las alertas y dónde pedir ayuda.',
    intro: 'AIMeter la construye y mantiene una sola persona, a la vista de todos. La mayoría de las respuestas están abajo; lo demás está a un issue de GitHub o un correo de distancia.',
    updated: 'Para AIMeter 2.0',
    sections: [
      {
        heading: 'Conectar en iPhone y iPad',
        paragraphs: [
          'Toca Conectar. AIMeter abre la página de inicio de sesión de tu proveedor en tu navegador (sirve cualquier método de acceso), apruebas, copias el código que te muestra y lo pegas de vuelta. Si quieres, ponle un nombre a la cuenta; puedes cambiarlo después desde el menú de la tarjeta. El token se guarda en el llavero y la app lo mantiene renovado por su cuenta.',
        ],
      },
      {
        heading: 'Conectar en el Mac',
        paragraphs: [
          'Cero configuración para tu primera cuenta si Claude Code está instalado y con sesión iniciada: AIMeter lee el inicio de sesión que ya guarda, en solo lectura, y nunca lo modifica. Cualquier cuenta adicional, o un Mac sin la CLI, inicia sesión igual que en iPhone. “Agregar cuenta” en el panel repite el flujo por cada inicio de sesión.',
        ],
      },
      {
        heading: 'Agradecimientos',
        paragraphs: [
          'La isla del notch le debe su sensación a dos proyectos de código abierto que llegaron antes. boring.notch, de TheBoredTeam en GitHub, fue la referencia de cómo debe moverse un panel en el notch: una ventana que nunca cambia de tamaño, una placa negra del tamaño de su propio contenido, un solo resorte que lleva tamaño, esquinas y sombra a la vez. Se leyó, no se copió; la isla de AIMeter es una implementación propia bajo licencia MIT. Vibe Island definió el formato de una línea que muestra la isla. Gracias a ambos.',
        ],
      },
    ],
    faqHeading: 'Preguntas frecuentes',
    faqs: [
      {
        q: 'La tarjeta dice “Iniciar sesión de nuevo”. ¿Qué pasó?',
        a: 'El proveedor rota el token de renovación en cada uso, así que un inicio de sesión compartido con otro cliente (la CLI en otra máquina, un segundo Mac) puede dejar de funcionar para AIMeter. Toca “Iniciar sesión de nuevo” en la tarjeta: repara la cuenta en su lugar, así que su historial, sus alertas y los widgets ya colocados siguen funcionando. No desconectes y vuelvas a agregar; eso crea una cuenta nueva y deja huérfano todo lo anterior.',
      },
      {
        q: 'Mi widget dice “actualizado hace 2 h”.',
        a: 'En iOS los widgets se actualizan solos en segundo plano dentro del presupuesto que les da el sistema, y la app los refresca cada vez que vuelve al frente. En el Mac los widgets solo muestran lo último que escribió la app de la barra de menús, así que déjala corriendo (puede hacerlo sin ningún ícono) y se mantienen al día.',
      },
      {
        q: '¿Dónde está la versión para Mac?',
        a: 'No está en la Mac App Store: la app de Mac lee el inicio de sesión que guarda tu herramienta de línea de comandos, y el sandbox de la tienda lo prohíbe. Compílala desde el código en unos minutos; con una cuenta de desarrollador gratuita basta para tus propias máquinas. El README lo explica paso a paso.',
      },
      {
        q: '¿Qué muestra la tercera fila?',
        a: 'La ventana real por modelo cuando tu plan la reporta. Cuando no, la fila se puede ocultar o mostrar tus créditos de uso, desde la pantalla de detalle de la cuenta (“Tercera fila de uso”). “Auto” decide por ti.',
      },
      {
        q: '¿La app ve mis conversaciones?',
        a: 'No. Llama a dos endpoints de solo lectura, tus ventanas de uso y tu perfil, con un token que no puede ejecutar prompts. La función opcional de Mac que lee los registros locales de la CLI decodifica solo conteos de tokens, nunca contenido.',
      },
      {
        q: '¿Cómo borro mis datos?',
        a: 'Desconecta la cuenta desde su pantalla de detalle. Eso borra su token, registro, historial y preferencias del dispositivo. No existe copia en ningún servidor.',
      },
      {
        q: '¿En qué idiomas está?',
        a: 'Inglés, español, alemán, francés, japonés, coreano, portugués de Brasil y chino simplificado, según el idioma del dispositivo.',
      },
      {
        q: '¿AIMeter está afiliada al proveedor?',
        a: 'No. Es un proyecto open source independiente, y lee un endpoint no documentado que puede cambiar en cualquier momento. La app lo dice en su propia pantalla de Privacidad.',
      },
    ],
    contactHeading: '¿Sigues atorado?',
    contact: 'Abre un issue con lo que esperabas y lo que viste, o escribe un correo. Ambos llegan a la misma persona.',
    email: 'Escribir a soporte',
    issues: 'Abrir un issue en GitHub',
  },
  notFound: { title: 'Aquí no hay nada', body: 'Esa página no existe, o se movió.', cta: 'Volver al inicio' },
  backHome: 'Volver a AIMeter',
} satisfies Dictionary
