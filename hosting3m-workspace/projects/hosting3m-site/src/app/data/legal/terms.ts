import type { LegalDoc } from './types';

export const TERMS: LegalDoc = {
  slug: 'terms',
  title: 'Condiciones de servicio',
  sections: [
    {
      heading: 'Quién presta el servicio',
      blocks: [
        {
          type: 'p',
          text: '{legalName}, con domicilio en {address} ("Hosting3M"), vende e integra servicios de infraestructura en la nube: renta de servidores VPS, registro de dominios y hosting, que contrata a IONOS como proveedor, además de servicios propios de automatización con IA, creación de páginas web y correo profesional. Al contratar o usar el sitio aceptas estas condiciones.',
        },
      ],
    },
    {
      heading: 'Precios y cobro',
      blocks: [
        {
          type: 'p',
          text: 'Los precios están en pesos mexicanos y se muestran más IVA. Se cobran por periodos anuales, por adelantado, y el precio publicado es el vigente en la fecha indicada en el sitio. Hosting3M emite la factura como revendedor. Los servicios con precio "cotiza" se acuerdan por escrito antes de contratar.',
        },
      ],
    },
    {
      heading: 'Modalidades',
      blocks: [
        {
          type: 'p',
          text: 'En *autoadministrado* pagas el precio del servicio y tú lo administras. En *administrado por Hosting3M* el precio incluye la instalación inicial, la configuración, la administración y el soporte personalizado. Lo que no esté descrito en el plan se cotiza aparte.',
        },
      ],
    },
    {
      heading: 'Renovación',
      blocks: [
        {
          type: 'p',
          text: 'Ningún servicio se renueva de forma automática: antes del vencimiento te avisaremos por correo, con 30 días de anticipación, para confirmar si deseas continuar. Si no se confirma y se paga la renovación, el servicio puede suspenderse o eliminarse conforme a las reglas del proveedor.',
        },
      ],
    },
    {
      heading: 'Cancelaciones y reembolsos',
      blocks: [
        {
          type: 'p',
          text: 'Para la renta de VPS y el hosting web aplican las políticas de desistimiento y reembolso del proveedor, que te indicaremos si las solicitas. Los servicios propios y la instalación inicial, una vez realizados, no son reembolsables.',
        },
      ],
    },
    {
      heading: 'Dominios',
      blocks: [
        {
          type: 'p',
          text: 'Tú eres el titular del dominio y respondes por la veracidad de los datos del registro. Su renovación y transferencia se rigen por las reglas del registrador y de la extensión.',
        },
      ],
    },
    {
      heading: 'Soporte',
      blocks: [
        {
          type: 'p',
          text: 'Atendemos por WhatsApp, correo y teléfono de lunes a viernes de 9:00 a 17:00 y sábados de 9:00 a 14:00, hora del Centro de México. No ofrecemos atención 24/7; respondemos tu primer mensaje en un día hábil dentro del horario de atención.',
        },
      ],
    },
    {
      heading: 'Disponibilidad',
      blocks: [
        {
          type: 'p',
          text: 'La infraestructura la operan proveedores externos (IONOS y, en su caso, Neubox). Hosting3M no garantiza disponibilidad ininterrumpida más allá de lo que el contrato del proveedor garantice para cada servicio, y trasladará las incidencias al proveedor.',
        },
      ],
    },
    {
      heading: 'Uso aceptable',
      blocks: [
        {
          type: 'p',
          text: 'Debes dar datos veraces y no usar los servicios para fines ilegales, fraudulentos, para enviar spam o para dañar a terceros. Podemos suspender un servicio que incumpla esta regla o las del proveedor.',
        },
      ],
    },
    {
      heading: 'Responsabilidad',
      blocks: [
        {
          type: 'p',
          text: 'Hosting3M responde por la prestación de sus propios servicios y no por daños causados por el mal uso, por causas fuera de su control o por fallas del proveedor, en la medida que la ley lo permita.',
        },
      ],
    },
    {
      heading: 'Propiedad intelectual',
      blocks: [
        {
          type: 'p',
          text: 'Los contenidos, marcas y logotipos del sitio pertenecen a {legalName}. Su uso requiere autorización escrita. Las marcas de IONOS y de terceros son de sus titulares.',
        },
      ],
    },
    {
      heading: 'Privacidad y cookies',
      blocks: [
        {
          type: 'p',
          text: 'El tratamiento de datos se rige por el [aviso de privacidad](/aviso-de-privacidad) y la [política de cookies](/politica-de-cookies) de este sitio.',
        },
      ],
    },
    {
      heading: 'Cambios',
      blocks: [
        {
          type: 'p',
          text: 'Podemos actualizar estas condiciones y las publicaremos con su fecha. Los cambios no afectan los servicios ya pagados hasta su siguiente renovación.',
        },
      ],
    },
    {
      heading: 'Ley y jurisdicción',
      blocks: [
        {
          type: 'p',
          text: 'Estas condiciones se rigen por las leyes de México, y las partes se someten a los tribunales competentes de Mérida, Yucatán, sin perjuicio de los derechos que la ley otorgue al consumidor. Última actualización: {lastUpdated}.',
        },
      ],
    },
  ],
};
