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

    // Paleta de Colores Eco-Hotel
    private ecoGreen: [number, number, number] = [46, 125, 50];       // Verde Bosque
    private lightOlive: [number, number, number] = [241, 245, 241];   // Verde muy tenue para filas
    private textColor: [number, number, number] = [60, 60, 60];       // Gris oscuro (mejor lectura que negro puro)
    private grayMuted: [number, number, number] = [120, 120, 120];

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

        // --- 2. ENCABEZADO (Header) ---
        // Título del Hotel
        doc.setFont("helvetica", "bold");
        doc.setFontSize(24);
        doc.setTextColor(this.ecoGreen[0], this.ecoGreen[1], this.ecoGreen[2]);
        doc.text(config.companyName, margin, 22);

        // Dirección
        doc.setFontSize(10);
        doc.setFont("helvetica", "normal");
        doc.setTextColor(this.grayMuted[0], this.grayMuted[1], this.grayMuted[2]);
        doc.text(config.companyAddress, margin, 28);

        // Bloque derecho (Fechas)
        doc.setFontSize(10);
        doc.setTextColor(this.textColor[0], this.textColor[1], this.textColor[2]);
        doc.text(`Fecha de emisión: ${today}`, pageWidth - margin, 22, { align: 'right' });
        doc.setFont("helvetica", "italic");
        if (config.showValidity !== false) {
            doc.text('Cotización válida por 15 días', pageWidth - margin, 32, { align: 'right' });
        }

        // Línea divisoria elegante
        doc.setDrawColor(this.ecoGreen[0], this.ecoGreen[1], this.ecoGreen[2]);
        doc.setLineWidth(0.5);
        doc.line(margin, 34, pageWidth - margin, 34);

        // --- 3. DATOS DEL CLIENTE ---
        doc.setFontSize(9);
        doc.setFont("helvetica", "bold");
        doc.setTextColor(this.grayMuted[0], this.grayMuted[1], this.grayMuted[2]);
        doc.text("PREPARADO PARA:", margin, 46);

        doc.setFontSize(12);
        doc.setTextColor(this.textColor[0], this.textColor[1], this.textColor[2]);
        doc.text(config.clientName, margin, 52);

        if (config.clientSubtitle) {
            doc.setFontSize(10);
            doc.setFont("helvetica", "normal");
            doc.text(config.clientSubtitle, margin, 57);
        }

        // Título del Documento
        doc.setFontSize(14);
        doc.setFont("helvetica", "bold");
        doc.setTextColor(this.ecoGreen[0], this.ecoGreen[1], this.ecoGreen[2]);
        doc.text(config.title.toUpperCase(), pageWidth / 2, 70, { align: 'center' });

        // --- 4. TABLA DE CONCEPTOS ---
        const tableBody = config.items.map((item, index) => [
            index + 1,
            item.concept + (item.description ? `\n(${item.description})` : ''),
            item.quantity,
            this.formatCurrency(item.unitPrice, currency),
            this.formatCurrency(item.total, currency)
        ]);

        const subtotal = config.items.reduce((acc, item) => acc + item.total, 0);

        // Matemáticas Financieras
        const totalRates = 1 + taxRate + ishRate;
        const baseAmount = subtotal / totalRates;
        const ivaAmount = baseAmount * taxRate;
        const ishAmount = baseAmount * ishRate;

        autoTable(doc, {
            startY: 76,
            head: [['#', 'Descripción', 'Cant.', 'Precio Unit.', 'Importe']],
            body: tableBody,
            theme: 'grid', // Cambiamos a grid para un look más definido
            headStyles: {
                fillColor: this.ecoGreen,
                textColor: 255,
                fontStyle: 'bold',
                halign: 'center'
            },
            bodyStyles: {
                textColor: this.textColor,
                fontSize: 10,
                cellPadding: 4
            },
            alternateRowStyles: {
                fillColor: this.lightOlive // Filas alternas con toque verde eco
            },
            columnStyles: {
                0: { halign: 'center', cellWidth: 12 },
                1: { cellWidth: 'auto' },
                2: { halign: 'center', cellWidth: 20 },
                3: { halign: 'right', cellWidth: 32 },
                4: { halign: 'right', cellWidth: 32 }
            }
        });

        // --- 5. TOTALES Y DESGLOSE ---
        let finalY = (doc as any).lastAutoTable.finalY + 10;

        const labelX = pageWidth - 55;
        const valueX = pageWidth - margin;

        doc.setFont("helvetica", "normal");
        doc.setFontSize(10);
        doc.setTextColor(this.textColor[0], this.textColor[1], this.textColor[2]);

        doc.text("Subtotal Base:", labelX, finalY, { align: 'right' });
        doc.text(this.formatCurrency(baseAmount, currency), valueX, finalY, { align: 'right' });

        if (config.showTaxes !== false && config.showTotals !== false) {
            finalY += 6;
            doc.text(`IVA (${(taxRate * 100).toFixed(0)}%):`, labelX, finalY, { align: 'right' });
            doc.text(this.formatCurrency(ivaAmount, currency), valueX, finalY, { align: 'right' });

            finalY += 6;
            doc.text(`ISH (${(ishRate * 100).toFixed(0)}%):`, labelX, finalY, { align: 'right' });
            doc.text(this.formatCurrency(ishAmount, currency), valueX, finalY, { align: 'right' });
        }

        // Total Final con Acento
        finalY += 10;
        doc.setFont("helvetica", "bold");
        doc.setFontSize(14);
        doc.text("TOTAL NETO:", labelX, finalY, { align: 'right' });

        // Pintamos el Total de Verde para que resalte
        doc.setTextColor(this.ecoGreen[0], this.ecoGreen[1], this.ecoGreen[2]);
        doc.text(this.formatCurrency(subtotal, currency), valueX, finalY, { align: 'right' });

        // --- 6. PIE DE PÁGINA (Footer) ---
        let footerY = (doc as any).lastAutoTable.finalY + 15;
        if (footerY < finalY + 20) footerY = finalY + 25;

        // Notas bancarias
        doc.setFont("helvetica", "normal");
        doc.setFontSize(9);
        doc.setTextColor(this.textColor[0], this.textColor[1], this.textColor[2]);

        if (config.footerTitle) {
            doc.setFont("helvetica", "bold");
            doc.text(config.footerTitle, margin, footerY);
            footerY += 5;
            doc.setFont("helvetica", "normal");
        }

        if (config.footerText) {
            config.footerText.forEach(line => {
                doc.text(line, margin, footerY);
                footerY += 5;
            });
        }

        // Eslogan Sustentable (Bottom center)
        const pageHeight = doc.internal.pageSize.height;
        doc.setFont("helvetica", "italic");
        doc.setFontSize(8);
        doc.setTextColor(this.grayMuted[0], this.grayMuted[1], this.grayMuted[2]);
        doc.text("Gracias por elegir el Hotel San José, Catazajá, Chiapas, México.", pageWidth / 2, pageHeight - 10, { align: 'center' });

        // --- 7. GUARDAR ---
        const cleanName = config.fileName.replace(/[^a-zA-Z0-9-_]/g, '_');
        doc.save(`${cleanName}.pdf`);
    }

    private formatCurrency(value: number, symbol: string): string {
        return `${symbol}${this.decimalPipe.transform(value, '1.2-2')}`;
    }
}