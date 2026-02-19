import { Injectable } from '@angular/core';
import jsPDF from 'jspdf';
import autoTable from 'jspdf-autotable';
import { DecimalPipe } from '@angular/common';
import { PdfExportConfig } from '../interfaces/pdf-export.interface';

@Injectable({
    providedIn: 'root'
})
export class PdfExportService {

    private decimalPipe = new DecimalPipe('en-US');

    constructor() { }

    public generate(config: PdfExportConfig): void {
        const doc = new jsPDF();
        const pageWidth = doc.internal.pageSize.width;
        const margin = 14;

        // --- 1. CONFIGURACIÓN ---
        const currency = config.currencySymbol || '$';
        const taxRate = config.taxRate !== undefined ? config.taxRate : 0.16;
        const ishRate = config.ishRate !== undefined ? config.ishRate : 0.02;
        const today = new Date().toLocaleDateString('es-MX', { day: 'numeric', month: 'long', year: 'numeric' });

        // --- 2. ENCABEZADO ---
        doc.setFontSize(18);
        doc.setTextColor(40, 55, 75);
        doc.text(config.companyName, margin, 20);

        doc.setFontSize(10);
        doc.setTextColor(100);
        doc.text(config.companyAddress, margin, 26);
        doc.text(`Fecha: ${today}`, pageWidth - margin, 26, { align: 'right' });

        doc.setDrawColor(200);
        doc.line(margin, 30, pageWidth - margin, 30);

        // --- 3. CLIENTE ---
        doc.setFontSize(11);
        doc.setTextColor(0);
        doc.text("ATENCIÓN A:", margin, 40);

        doc.setFont("helvetica", "bold");
        doc.text(config.clientName, margin, 46);

        if (config.clientSubtitle) {
            doc.setFont("helvetica", "normal");
            doc.text(config.clientSubtitle, margin, 52);
        }

        doc.setFontSize(14);
        doc.setTextColor(40, 55, 75);
        doc.text(config.title.toUpperCase(), pageWidth / 2, 65, { align: 'center' });

        // --- 4. TABLA ---
        const tableBody = config.items.map((item, index) => [
            index + 1,
            item.concept + (item.description ? `\n(${item.description})` : ''),
            item.quantity,
            this.formatCurrency(item.unitPrice, currency),
            this.formatCurrency(item.total, currency)
        ]);

        const subtotal = config.items.reduce((acc, item) => acc + item.total, 0);

        // Cálculo inverso (Montos incluyen impuestos)
        const totalRates = 1 + taxRate + ishRate;
        const baseAmount = subtotal / totalRates;
        const ivaAmount = baseAmount * taxRate;
        const ishAmount = baseAmount * ishRate;

        autoTable(doc, {
            startY: 70,
            head: [['#', 'Concepto', 'Cant.', 'P. Unit.', 'Importe']],
            body: tableBody,
            theme: 'striped',
            headStyles: { fillColor: [44, 62, 80], textColor: 255 },
            styles: { fontSize: 10, cellPadding: 3 },
            columnStyles: {
                0: { cellWidth: 10 },
                1: { cellWidth: 'auto' },
                2: { halign: 'center', cellWidth: 20 },
                3: { halign: 'right', cellWidth: 30 },
                4: { halign: 'right', cellWidth: 30 }
            }
        });

        // --- 5. TOTALES (AJUSTADO) ---
        let finalY = (doc as any).lastAutoTable.finalY + 10;

        // Coordenadas de alineación derecha
        const labelX = pageWidth - 55;
        const valueX = pageWidth - margin;

        // 1. Subtotal e Impuestos (Tamaño 10, igual que la tabla)
        doc.setFont("helvetica", "normal");
        doc.setFontSize(10); // Aseguramos tamaño estándar

        doc.text("Subtotal Base:", labelX, finalY, { align: 'right' });
        doc.text(this.formatCurrency(baseAmount, currency), valueX, finalY, { align: 'right' });

        finalY += 6;
        doc.text(`IVA (${(taxRate * 100).toFixed(0)}%):`, labelX, finalY, { align: 'right' });
        doc.text(this.formatCurrency(ivaAmount, currency), valueX, finalY, { align: 'right' });

        finalY += 6;
        doc.text(`ISH (${(ishRate * 100).toFixed(0)}%):`, labelX, finalY, { align: 'right' });
        doc.text(this.formatCurrency(ishAmount, currency), valueX, finalY, { align: 'right' });

        // 2. TOTAL FINAL (Tamaño 14 y más espacio)
        finalY += 10; // Damos un poco más de aire antes del total
        doc.setFont("helvetica", "bold");
        doc.setFontSize(14); // <--- AUMENTADO (Antes era 12)

        doc.text("TOTAL NETO:", labelX, finalY, { align: 'right' });
        doc.text(this.formatCurrency(subtotal, currency), valueX, finalY, { align: 'right' });

        // --- 6. PIE ---
        if (config.footerTitle || config.footerText) {
            let footerY = (doc as any).lastAutoTable.finalY + 10;
            // Si la tabla es larga y choca con los totales, bajamos el pie de página
            if (footerY < finalY + 15) footerY = finalY + 25;

            doc.setFont("helvetica", "normal");
            doc.setFontSize(9);
            doc.setTextColor(0);

            if (config.footerTitle) {
                doc.text(config.footerTitle, margin, footerY);
                footerY += 5;
            }

            doc.setFont("helvetica", "bold");
            if (config.footerText) {
                config.footerText.forEach(line => {
                    doc.text(line, margin, footerY);
                    footerY += 5;
                });
            }
        }

        const cleanName = config.fileName.replace(/[^a-zA-Z0-9-_]/g, '_');
        doc.save(`${cleanName}.pdf`);
    }

    private formatCurrency(value: number, symbol: string): string {
        return `${symbol}${this.decimalPipe.transform(value, '1.2-2')}`;
    }
}