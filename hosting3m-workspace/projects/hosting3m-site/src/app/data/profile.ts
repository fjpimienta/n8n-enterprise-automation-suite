/**
 * Profile page (/fjpimienta). Approved content only. Do NOT add certifications, past employers by name, language levels,
 * course lists, GitHub or any personal email or phone: contact goes through the business data in core/site.config.ts.
 */
export const PROFILE = {
  name: 'Francisco Jesús Pérez Pimienta',
  title: 'Ingeniero en Sistemas Computacionales, Maestro en Administración de Proyectos',
  location: 'Mérida, Yucatán',
  summary:
    'Francisco Jesús Pérez Pimienta es ingeniero en Sistemas Computacionales y maestro en Administración de Proyectos, radicado en Mérida, Yucatán, con más de 20 años de experiencia en ingeniería de sistemas y gestión de proyectos. Fundó Hosting3M en enero de 2020 para ofrecer soluciones en la nube y automatización de procesos con agentes de IA. Su trabajo combina arquitectura y desarrollo full-stack (C#, .NET Core, JavaScript), integración de sistemas, DevOps con Docker y VPS Linux, bases de datos (PostgreSQL, SQL Server, MongoDB) y automatización con n8n y modelos de lenguaje.', // MARKETING-REVIEW
  areasTitle: 'Áreas de trabajo',
  areas: [
    'Desarrollo full-stack',
    'Liderazgo de proyectos de TI (líder de proyectos de tecnología e integración durante más de diez años)',
    'Integración de sistemas',
    'Automatización (n8n, LLMs)',
    'DevOps (Docker, VPS Linux)',
    'Bases de datos',
  ], // MARKETING-REVIEW
  educationTitle: 'Formación',
  education: [
    { degree: 'Maestría en Administración de Proyectos', school: 'Universidad para la Cooperación Internacional' },
    { degree: 'Ingeniería en Sistemas Computacionales', school: 'Instituto Tecnológico de Villahermosa' },
  ],
  linkedin: { label: 'LinkedIn', url: 'https://www.linkedin.com/in/fjpimienta' },
  contactTitle: 'Contacto',
  photo: { src: '/images/profile-400.webp', width: 400, height: 400, alt: 'Fotografía de Francisco Jesús Pérez Pimienta' },
} as const;
