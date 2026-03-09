# Planning Guide

Una landing page ultra-minimalista estilo Apple e Internxt para Azure Copilot Studio, con diseño premium, espacio en blanco generoso y mensajes de marketing que convierten.

**Experience Qualities**:
1. **Refinado** - Estética ultra-limpia con tipografía grande y espacios amplios que transmiten lujo y simplicidad
2. **Fluido** - Animaciones suaves y transiciones que se sienten naturales y premium
3. **Impactante** - Mensajes claros y poderosos que capturan la atención y convierten

**Complexity Level**: Content Showcase (information-focused)
Landing page de marketing premium diseñada para convertir visitantes en usuarios activos del repositorio, con énfasis en estética minimalista y mensajes persuasivos.

## Essential Features

### Hero Section Ultra-Minimalista
- **Functionality**: Pantalla completa con título masivo y CTA prominentes
- **Purpose**: Impacto inmediato con mensaje claro y convincente estilo Apple
- **Trigger**: Carga de página
- **Progression**: Fade in suave → Título gigante aparece palabra por palabra → Subtítulo se desvanece → CTAs con animación de escala
- **Success criteria**: Tipografía grande (104px desktop), espacios amplios, scroll parallax fluido

### Sección de Estadísticas
- **Functionality**: Números impresionantes con iconos para credibilidad
- **Purpose**: Validación social y prueba de adopción masiva
- **Trigger**: Scroll a la vista
- **Progression**: Usuario hace scroll → Números aparecen con fade in → Iconos con efecto duotone → Información contextual visible
- **Success criteria**: Estadísticas reales y convincentes, animación secuencial

### Grid de Features Minimalista
- **Functionality**: Cards limpias con hover effects sutiles
- **Purpose**: Mostrar capacidades clave sin saturar visualmente
- **Trigger**: Scroll into view
- **Progression**: Scroll → Cards aparecen escalonadas → Hover eleva la card → Click abre GitHub
- **Success criteria**: Máximo espacio en blanco, bordes sutiles, sombras suaves

### CTA Section con Alto Contraste
- **Functionality**: Sección oscura (negro) con fondo invertido para impacto
- **Purpose**: Conversión final con contraste dramático
- **Trigger**: Scroll a la sección
- **Progression**: Fade in del fondo oscuro → Elementos blancos aparecen → CTAs con hover glow
- **Success criteria**: Contraste total (fondo negro, texto blanco), efectos de blur en el fondo

## Edge Case Handling
- **Idioma español**: Todo el contenido en español para el mercado objetivo
- **Mobile First**: Tipografía responsive que escala de 104px → 56px en móvil
- **Navegación suave**: Scroll behavior smooth y parallax que funciona en todos los navegadores
- **Links externos**: Todos los links de GitHub abren en nueva pestaña preservando la experiencia

## Design Direction
Ultra-minimalismo de lujo - inspirado en Apple e Internxt - donde cada pixel cuenta. Espacios en blanco amplísimos, tipografía gigante, paleta monocromática con un toque de color azul estratégico para CTAs. La página debe sentirse como un producto premium, no como documentación técnica.

## Color Selection
Paleta monocromática ultra-limpia con negro puro, blanco puro y un azul vibrante como único acento de color.

- **Primary Color**: Negro Puro (oklch(0.15 0 0)) - Texto principal y sección CTA, transmite sofisticación y seriedad
- **Secondary Colors**: 
  - Blanco Puro (oklch(1 0 0)) - Fondo principal, máxima claridad y amplitud
  - Gris Suave (oklch(0.97 0 0)) - Fondos de secciones alternas, separación sutil
  - Gris Texto (oklch(0.45 0 0)) - Texto secundario, jerarquía visual
- **Accent Color**: Azul Vibrante (oklch(0.50 0.24 252)) - CTAs y elementos interactivos, único toque de color
- **Foreground/Background Pairings**:
  - Blanco (oklch(1 0 0)): Negro (oklch(0.15 0 0)) - Ratio 18.7:1 ✓✓
  - Negro (oklch(0.15 0 0)): Blanco (oklch(1 0 0)) - Ratio 18.7:1 ✓✓
  - Azul Accent (oklch(0.50 0.24 252)): Blanco (oklch(1 0 0)) - Ratio 5.8:1 ✓
  - Gris Suave (oklch(0.97 0 0)): Negro (oklch(0.15 0 0)) - Ratio 17.3:1 ✓✓

## Font Selection
Inter en pesos múltiples (300-700) para crear jerarquía masiva - tipografía GRANDE que domina la pantalla como en productos Apple, con letra tracking ajustada para máximo impacto visual.

- **Typographic Hierarchy**:
  - H1 (Hero Title): Inter Semibold / 104px desktop, 56px móvil / -0.04em letter spacing / Line height 0.95 (ultra-tight para impacto)
  - H2 (Section Headings): Inter Semibold / 64px desktop, 48px móvil / -0.03em letter spacing / Line height 1.1
  - H3 (Feature Titles): Inter Semibold / 24px / Normal spacing / Line height 1.3
  - Body Large: Inter Light / 22px / Normal spacing / Line height 1.6 (subtítulos)
  - Body Regular: Inter Light / 17px / Normal spacing / Line height 1.6 (descripciones)
  - Small: Inter Medium / 15px / Normal spacing / Line height 1.5 (navegación, footer)

## Animations
Animaciones ultra-suaves y casi imperceptibles - scroll parallax en el hero, fade-ins lentos (0.7s-0.8s) para secciones, hover effects con scale mínimo (1.02), y transiciones largas (300-500ms) que se sienten premium y fluidas. Todo debe sentirse como flotando, no saltando.

## Component Selection

- **Components**:
  - Button: Rounded-full (pills) con h-[56px] para máximo impacto táctil
  - Card: Bordes ultra-sutiles (border-border), sombras difusas largas, rounded-3xl
  - Sin Badges, sin Separators visibles - minimalismo extremo
  
- **Customizations**:
  - Hero con parallax scroll que reduce opacity y scale
  - Sección CTA con fondo negro total y efectos de blur en background
  - Botones con rounded-full exclusivamente (no rectangulares)
  - Cards flotantes con hover que eleva sutilmente (-translate-y-1)
  
- **States**:
  - Buttons: Rest (bg sólido), Hover (scale 1.02 + shadow-xl), Active (mantener), Focus (invisible, no rings)
  - Cards: Rest (shadow sutil), Hover (shadow-2xl + translate-y), Active (igual), Focus (sin ring visible)
  - Links: Rest (color estándar), Hover (color change), sin underlines
  
- **Icon Selection**:
  - Phosphor Icons weight="duotone" para iconos decorativos
  - Phosphor Icons weight="bold" para CTAs y navegación
  - ArrowRight: Indicadores de acción
  - GithubLogo: Links al repositorio
  - Code, ChartLine, Users, Rocket: Iconografía de features
  
- **Spacing**:
  - Section padding: py-32 md:py-40 (espacios masivos)
  - Container max-width: max-w-[1400px] (wide pero controlado)
  - Card gaps: gap-6 (respiración entre cards)
  - Vertical rhythm: space-y-8 para secciones grandes
  - Button padding: px-8 h-[56px] (botones grandes y táctiles)
  
- **Mobile**:
  - Hero text: 104px → 56px (escala significativa)
  - Section headings: 64px → 48px
  - Grid layout: 3 cols → 2 cols → 1 col con breakpoints limpios
  - Padding: py-40 → py-20 en móvil
  - Botones mantienen h-[56px] en móvil (táctil friendly)
  - Stats grid: 4 cols → 2 cols en móvil
