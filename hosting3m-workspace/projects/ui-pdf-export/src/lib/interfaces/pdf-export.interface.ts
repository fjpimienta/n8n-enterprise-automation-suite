export interface PdfExportItem {
    concept: string;       // Ej: "Habitación 101"
    description?: string;  // Ej: "Noches del 21 al 28"
    quantity: number;      // Ej: 7
    unitPrice: number;     // Ej: 500.00
    total: number;         // Ej: 3500.00
}

export interface PdfExportConfig {
    fileName: string;
    title: string;

    // Datos del Emisor
    companyName: string;
    companyAddress: string;

    // Datos del Cliente
    clientName: string;
    clientSubtitle?: string;

    // Contenido
    items: PdfExportItem[];

    // Configuración
    currencySymbol?: string;
    taxRate?: number;
    ishRate?: number;

    // Pie de página
    footerTitle?: string;
    footerText?: string[];

    showTaxes?: boolean;
    showTotals?: boolean;
    showValidity?: boolean;
}