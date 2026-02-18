## Propuesta Técnica para Migrar el Layout de `projects/dashboard` al Estilo de `projects/pista-hielo`

### 1. Mapeo de Componentes
Identificaremos los componentes que se clonarán o adaptarán de `projects/pista-hielo/src/app/shared/layout/` para su uso en `dashboard`:

- **Sidebar**: Se adaptará para incluir los ítems de navegación específicos del Dashboard.
- **Header**: Se clonará y personalizará para reflejar el branding y la funcionalidad del Dashboard.
- **MainLayout**: Se ajustará para integrar el nuevo Sidebar y Header, asegurando que el contenido principal se adapte al nuevo diseño.

### 2. Estructura del Sidebar
Los ítems de navegación propuestos para el Sidebar del Dashboard son:

- **Dashboard**: Ruta principal del Dashboard.
- **Reservas**: Gestión de reservas.
- **Huéspedes**: Información y gestión de huéspedes.
- **Personal**: Administración del personal.
- **Inventario**: Control de inventario.

### 3. Plan de Estilos
Para sincronizar las variables CSS de `pista-hielo` y asegurar que el Dashboard adopte el mismo 'Look & Feel', se seguirán estos pasos:

- **Variables CSS**: Importar las variables CSS de `pista-hielo` en el archivo de estilos del Dashboard.
- **Dark Mode**: Implementar un esquema de colores que refleje el modo oscuro utilizado en `pista-hielo`.
- **Colores y Bordes**: Alinear los colores de fondo, texto y bordes con los definidos en `pista-hielo`, asegurando consistencia visual.

### 4. Impacto en `App.Component`
Los cambios necesarios en el punto de entrada (`app.component.ts`) para soportar el nuevo Layout incluirán:

- **Importación de Componentes**: Importar los nuevos componentes de Sidebar, Header y MainLayout.
- **Modificación de la Plantilla**: Actualizar la plantilla del componente principal para incluir el nuevo diseño, asegurando que el Sidebar y Header se integren correctamente.
- **Configuración de Rutas**: Ajustar las rutas en el módulo de enrutamiento para reflejar la nueva estructura de navegación.

Esta propuesta técnica proporciona un marco claro para la migración del layout, asegurando que se mantenga la coherencia visual y funcional entre los diferentes componentes del sistema.