import type { Dictionary } from './types'

export const es = {
  meta: {
    title: 'AIMeter: Tus límites de IA, de un vistazo',
    description:
      'AIMeter te dice cuánto te queda de tus suscripciones de IA, justo en el notch de tu Mac y en el iPhone: límites por sesión, semana y modelo, una mascota por cada sesión de código, widgets y la pantalla de bloqueo. Gratis, open source, sin servidor.',
  },
  nav: {
    features: 'Funciones',
    mac: 'Mac',
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
    line1: 'Tus límites de IA,',
    line2: 'justo en el *notch*.',
    sub: 'Cada límite de tus suscripciones de IA y cuándo se reinicia, en el notch de tu Mac. Y en iPhone y iPad, con widgets y la pantalla de bloqueo.',
    appStore: 'Descárgala en el App Store',
    appStoreSmall: 'Descárgala en el',
    github: 'Ver en GitHub',
    macDownload: 'Descargar para Mac',
    macDownloadSmall: 'Descargar para',
    platforms: 'iPhone · iPad · Mac',
    version: 'Versión',
    phoneAlt: 'Panel de AIMeter en iPhone: dos cuentas, cada una con límites de sesión, semana y modelo como barras con cuenta regresiva.',
  },
  demo: {
    label: 'La isla del notch en acción',
    scenes: [
      { pill: 'Límites', title: 'Tus límites, a un vistazo.' },
      { pill: 'Sesiones', title: 'Una mascota por cada sesión en curso.' },
      { pill: 'Te necesita', title: 'Entérate cuando una sesión te necesita.' },
    ],
  },
  statement: 'Cada límite por el que pagas, en un solo lugar. Sin servidor, sin cuenta, sin analíticas.',
  features: {
    heading: 'Lo que *hace*',
    sub: 'Todo viene directo de los números de tu proveedor.',
    listLabel: 'Funciones',
    carousel: { role: 'carrusel', slide: 'diapositiva', position: '{n} de {total}', dots: 'Elige una función', previous: 'Función anterior', next: 'Función siguiente' },
    items: [
      {
        id: 'limits',
        title: 'Todos tus límites, de un vistazo',
        body: 'Los límites de cada cuenta, el más cercano a agotarse al frente, con su barra, su porcentaje y cuándo se reinicia.',
        points: ['Más de un servicio de IA', 'Restante o usado, tú eliges'],
        imageAlt: 'Panel con dos cuentas y sus barras de límites.',
      },
      {
        id: 'widgets',
        title: 'Widgets que llevan la cuenta',
        body: 'Widgets chico, mediano y grande, la pantalla de bloqueo y una Live Activity con la cuenta regresiva.',
        points: ['Una cuenta o todas', 'En iPhone se actualizan solos'],
        imageAlt: 'Pantalla de inicio con los widgets chico, mediano y grande de AIMeter.',
      },
      {
        id: 'history',
        title: 'Cada reinicio, graficado',
        body: 'El uso de cada límite en el último día, semana o mes, con cada reinicio marcado.',
        points: ['30 días guardados en tu dispositivo', 'Una minigráfica en cada tarjeta'],
        imageAlt: 'Gráfica del uso semanal en 30 días con marcas de reinicio.',
      },
      {
        id: 'alerts',
        title: 'Alertas antes de la pared',
        body: 'Avisos locales cuando te acercas a un límite, cuando lo alcanzas o cuando se reinicia antes.',
        points: ['Tu propio umbral', 'Sin servicio push'],
        imageAlt: 'Interruptores de notificaciones de una cuenta.',
      },
      {
        id: 'pace',
        title: 'Conoce tu ritmo',
        body: 'Cada ventana te dice si vas al ritmo, adelantado o atrasado, y cuál se agotará antes.',
        points: ['Aprende tu ritmo antes de opinar', 'Un pronóstico por ventana'],
        imageAlt: 'Detalle de cuenta con el ritmo por fila y la tarjeta de Pronóstico.',
      },
      {
        id: 'accounts',
        title: 'Cada cuenta, su propio ícono',
        body: 'Todas las cuentas que quieras, cada una con su nombre y su ícono, en todas partes.',
        points: ['Arrastra para reordenar', 'Modo oscuro incluido'],
        imageAlt: 'Panel en modo oscuro con dos cuentas e íconos personalizados.',
      },
    ],
  },
  phone: {
    personal: 'Personal',
    work: 'Work',
    plan: 'Demo',
    session: 'Sesión de 5 horas',
    weekly: 'Semanal',
    weeklyTopModel: 'Semanal · Modelo top',
    credits: 'Créditos',
    resetsIn: 'Se reinicia en {t}',
    updatedNow: 'Actualizado ahora mismo',
    updatedMinutes: 'Actualizado hace {n} min',
    onPace: 'En ritmo',
    ahead: 'Adelantado',
    behind: 'Atrasado',
    rateLimits: 'Límites de uso',
    history: 'Historial',
    forecast: 'Pronóstico',
    windowPills: ['Sesión', 'Semana', 'Modelo top'],
    ranges: ['24 h', '7 días', '30 días'],
    chartLabels: [
      ['3 a. m.', '9 a. m.', '3 p. m.'],
      ['lun', 'mié', 'vie', 'dom'],
      ['20 sept', '27 sept', '4 oct', '11 oct'],
    ],
    runsOutEarly: 'Se agota ~{t} antes',
    forecastNote: 'Proyectado según tu ritmo promedio en esta ventana. Se ajusta a medida que usas más.',
    historyNote: 'Porcentaje del límite usado, muestreado cada vez que AIMeter o un widget actualiza y guardado en este dispositivo 30 días.',
    used: 'usado',
    usedCap: 'Usado',
    week: 'Semana',
    topModel: 'Modelo top',
    nearing: '{w} cerca de su límite',
    nearingBody: 'Vas en {n}% de esta ventana.',
    refilled: '{w} se recargó antes',
    refilledBody: 'Tu límite de {w} se reinició antes de lo previsto. Capacidad completa disponible.',
    now: 'ahora',
    date: 'jueves, 15 de octubre',
  },
  mac: {
    heading: 'Cualquier Mac, *cualquier pantalla*',
    sub: '¿Sin notch? AIMeter dibuja uno arriba de tu pantalla, o una pastilla en la barra de menús. ¿Prefieres un ícono? Elige entre seis estilos.',
    styles: ['Medidor con el número', 'Solo medidor', 'Solo número', 'Barra', 'Batería', 'Dos o tres ventanas lado a lado'],
    extras: ['Ícono del Dock opcional', 'Abre al iniciar sesión', 'Se actualiza sola', 'Atajos de teclado'],
    note: 'Fuera de la Mac App Store: un zip notarizado por Apple, para macOS 14 o posterior.',
    download: 'Descargar para Mac',
    build: 'Compílala desde el código',
  },
  privacy: {
    heading: 'Privada *por diseño*',
    sub: 'Cada afirmación de aquí se puede verificar en el código.',
    points: [
      { title: 'Sin servidor, sin cuenta', body: 'Tu uso va de tu proveedor a tu dispositivo, sin nada en medio.' },
      { title: 'Los tokens viven en el llavero', body: 'Cifrados por el sistema. AIMeter pide un permiso de solo lectura, nunca uno que ejecute prompts.' },
      { title: 'Sin analíticas, sin rastreo', body: 'Ni analíticas, ni anuncios, ni reportes de fallos, en la app ni en este sitio.' },
      { title: 'Tuyo para borrarlo', body: 'Desconectar una cuenta borra su token y su historial. En la nube no hay nada, salvo que actives la sincronización con iCloud, que puedes apagar cuando quieras.' },
    ],
    cta: 'Lee la política de privacidad',
  },
  openSource: {
    heading: 'Open source, *gratis para siempre*',
    sub: 'Licencia MIT. Sin planes ni funciones bloqueadas.',
    points: [
      { title: 'Audítala tú mismo', body: 'Los scripts del repo imprimen el JSON exacto que lee la app.' },
      { title: 'Compila la app de Mac', body: 'Clona, pon tu Team ID y compila. Basta una cuenta de desarrollador gratuita.' },
      { title: 'SwiftUI puro', body: 'iOS 17+ y macOS 14+, sin dependencias.' },
    ],
    languagesLabel: 'Disponible en',
    languages: 'inglés, español, alemán, francés, japonés, coreano, portugués de Brasil y chino simplificado',
    github: 'Dale una estrella en GitHub',
  },
  closing: {
    eyebrow: 'Gratis en el App Store para iPhone y iPad, y para descargar en el Mac.',
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
    updated: 'Última actualización: 19 de octubre de 2026',
    sections: [
      {
        heading: 'Qué sale de tu dispositivo',
        paragraphs: ['Solo peticiones HTTPS a los proveedores cuyo uso le pediste a AIMeter que lea (y, en la Mac, a GitHub para las actualizaciones), y nada hacia nosotros, porque no hay un “nosotros” al que enviarlo.'],
        bullets: [
          'Claude. api.anthropic.com: /api/oauth/usage para tus límites y cifras de gasto, y /api/oauth/profile para resolver el nombre de tu plan (se vuelve a consultar como máximo cada 6 horas). claude.ai y console.anthropic.com: el intercambio OAuth estándar al conectar una cuenta desde la app. Inicias sesión en la página del propio proveedor en tu navegador, nunca en una vista web incrustada, y pegas de vuelta el código que te muestra.',
          'Codex. chatgpt.com: /backend-api/wham/usage para tus límites de Codex, las mismas cifras que muestra /status en el CLI de Codex. auth.openai.com: el inicio de sesión por código de dispositivo de ChatGPT (escribes un código de un solo uso en su página, en tu navegador) y la renovación del token que le sigue. En la Mac se puede leer en su lugar el inicio de sesión que el CLI de Codex guarda en ~/.codex, sin modificarlo nunca.',
          'GitHub Copilot. github.com: el inicio de sesión por código de dispositivo de GitHub, sin pedir ningún permiso. api.github.com: el endpoint de cuotas de Copilot que leen sus complementos para editores, cuya respuesta trae tu id de usuario, usado para distinguir la cuenta en tus otros dispositivos.',
          'status.claude.com, status.openai.com y githubstatus.com: una petición anónima a la página pública de estado de cada proveedor conectado en cada actualización, para distinguir un incidente del servicio de un problema con tu cuenta. No lleva nada sobre ti y se puede apagar en Ajustes.',
          'api.github.com y github.com (solo en Mac): una vez al día, una consulta para saber si hay una versión más nueva de AIMeter y, si la hay, su descarga desde la página de versiones del proyecto. No lleva nada sobre ti y se puede apagar en Ajustes.',
          'iCloud (opcional, apagado por defecto): con «Sincronizar preferencias e historial» activado en Ajustes, tus preferencias de visualización y el historial de uso de cada cuenta (los porcentajes y sus fechas, nada más) van a tu propio almacén de valores de iCloud, con tu Cuenta de Apple, para llegar a tus otros dispositivos con AIMeter. Los tokens de inicio de sesión nunca, y no hay ningún servidor nuestro de por medio. Al apagarlo se elimina lo que AIMeter guardó allí.',
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
        heading: 'Sesiones de la línea de comandos en el notch (Mac)',
        paragraphs: [
          'Encendido mientras la isla del notch lo está, y se apaga con un interruptor en Ajustes. Para mostrar qué sesiones de Claude Code están trabajando, esperando tu permiso o terminadas, AIMeter sigue los registros de sesión en ~/.claude/projects y solo lee qué es cada registro y cuándo se escribió, además del título y la carpeta de cada sesión: nunca prompts, respuestas ni entradas de herramientas. No guarda nada ni envía nada a ningún lado. Si instalas los hooks opcionales, AIMeter agrega una entrada por evento a ~/.claude/settings.json (respalda el archivo antes y conserva todo lo demás), y Claude Code le pasa cada evento a AIMeter por una conexión privada en ese Mac a la que solo tu cuenta tiene acceso; AIMeter lee de qué sesión se trata y qué pasó, y descarta el resto. “Quitar” saca esas entradas de nuevo. La función no existe en iOS.',
        ],
      },
      {
        heading: 'Accesibilidad (Mac, opcional)',
        paragraphs: [
          'Solo si activas «No tapar la barra de menús» en Ajustes, macOS te pide permitir AIMeter en Accesibilidad. AIMeter lo usa para una sola cosa: saber dónde están los títulos de menú de la app abierta y los íconos de la barra de menús, para que la isla del notch se encoja antes de taparlos. No lee nada más, no cambia nada, no guarda nada y no envía nada a ningún lado.',
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
    updated: 'Para AIMeter 3.2',
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
          'La isla del notch le debe su sensación a tres proyectos que llegaron antes. boring.notch, de TheBoredTeam en GitHub, fue la referencia de cómo debe moverse un panel en el notch: una ventana que nunca cambia de tamaño, una placa negra del tamaño de su propio contenido, un solo resorte que lleva tamaño, esquinas y sombra a la vez. Se leyó, no se copió; la isla de AIMeter es una implementación propia bajo licencia MIT. Vibe Island definió el formato de una línea que muestra la isla, y cómo se lee una sesión con la isla cerrada: sus mascotas en un extremo, el conteo en el otro. Atoll, de Ebullioscopic, mostró las opciones que necesita una pantalla sin notch, de la pastilla a ocultarse hasta que llega el cursor; se estudió igual. Gracias a los tres.',
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
        a: 'No está en la Mac App Store: la app de Mac lee el inicio de sesión que guarda tu herramienta de línea de comandos, y el sandbox de la tienda lo prohíbe. Descárgala de las versiones del proyecto (Descargar para Mac, un zip notarizado por Apple) o compílala desde el código; el README explica ambas. Desde la 3.0 se mantiene al día sola.',
      },
      {
        q: '¿Qué son las mascotas junto al notch?',
        a: 'Cada sesión de Claude Code en curso en esa Mac tiene una mascota de píxeles: camina mientras la sesión trabaja, se agita junto a un ! amarillo cuando necesita tu permiso y se duerme unos segundos cuando termina. El conteo del otro lado del notch dice cuántas sesiones hay. Detén el cursor en el notch para ver el nombre de la sesión y qué está haciendo, o haz clic para ver todas las sesiones y tu uso. En Ajustes, la pestaña Claude Code apaga las mascotas, el nombre o toda la función, e instala los hooks opcionales que avisan a AIMeter en cuanto una sesión pide permiso.',
      },
      {
        q: '¿Dónde está el tutorial?',
        a: 'Se abre la primera vez que abres AIMeter, una parte a la vez, cada una con un botón que la activa. Para verlo otra vez: Ajustes, Ver el tutorial (en el Mac, en General).',
      },
      {
        q: '¿Cómo se actualiza la app de Mac?',
        a: 'Revisa las versiones del proyecto en GitHub un minuto después de abrirse y luego una vez al día, descarga la versión nueva en segundo plano y solo la conserva si cuadra: la misma firma, la misma app, la versión anunciada. Entonces te avisa, y solo la instala cuando eliges Reiniciar y actualizar. En Ajustes, General tiene la revisión diaria y Buscar ahora; el menú de la app tiene Buscar actualizaciones.',
      },
      {
        q: '¿Qué muestra la tercera fila?',
        a: 'La ventana real por modelo cuando tu plan la reporta. Cuando no, la fila se puede ocultar o mostrar tus créditos de uso, desde la pantalla de detalle de la cuenta (“Tercera fila de uso”). “Auto” decide por ti.',
      },
      {
        q: '¿La app ve mis conversaciones?',
        a: 'No. Llama a dos endpoints de solo lectura, tus ventanas de uso y tu perfil, con un token que no puede ejecutar prompts. La función opcional de Mac que lee los registros locales de la CLI decodifica solo conteos de tokens, nunca contenido. La vista de sesiones del notch lee solo qué es cada registro y cuándo se escribió, más el título y la carpeta de cada sesión.',
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
