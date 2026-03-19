export interface PdfExportItem {
    concept: string;       // Ej: "Habitación Doble"
    description?: string;  // (Opcional para notas extra, ya no usamos los paréntesis anidados)
    quantity: number;      // Cantidad de habitaciones
    unitPrice: number;     // Subtotal neto base de 1 habitación (Legacy para cálculos)
    total: number;         // Importe Total (unitPrice * quantity)
    dailyRate?: number;    // Precio neto por noche
    nights?: number;       // Cantidad de noches
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