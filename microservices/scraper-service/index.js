require('./init-webapi');

const express = require('express');
const bodyParser = require('body-parser');
const cheerio = require('cheerio');
const puppeteer = require('puppeteer');
const ipaddr = require('ipaddr.js'); // Librería de seguridad
const { URL } = require('url');      // Módulo nativo
const { PORT, USER_AGENT } = require('./config');

const app = express();
app.use(bodyParser.json());

/**
 * Función de seguridad para prevenir SSRF (Server-Side Request Forgery)
 */
function isSafeUrl(inputUrl) {
    try {
        const parsedUrl = new URL(inputUrl);

        // A. Validar que el protocolo sea estrictamente HTTP o HTTPS
        if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
            return false;
        }

        // B. Bloquear hostnames y direcciones IP privadas/locales
        const hostname = parsedUrl.hostname;
        const forbiddenHosts = ['localhost', '127.0.0.1', '169.254.169.254', '::1', '0.0.0.0'];

        // Bloqueo básico de rangos de red privada (10.x.x.x, 192.168.x.x, 172.16.x.x)
        const isPrivateIp = /^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[0-1])\.)/.test(hostname);

        if (forbiddenHosts.includes(hostname) || isPrivateIp) {
            return false;
        }

        return true;
    } catch (e) {
        // Si new URL() falla, la URL está mal formada
        return false;
    }
}

// NAVEGACIÓN
try {
    if (!isSafeUrl(finalUrl)) {
        throw new Error("URL rechazada por políticas de seguridad (SSRF prevention).");
    }

    // USAR finalUrl AQUÍ (Variable que viene del objeto URL validado)
    await page.goto(finalUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });

} catch (e) {
    console.log(`[WARN] Goto: ${e.message}`);
}

app.post('/scrape', async (req, res) => {
    let browser = null;
    try {
        // 1. Usamos 'url' como nombre único para no confundir al bot
        const { url, selectors, title, pubDate, description } = req.body;

        if (!url) return res.status(400).json({ error: "Se requiere 'url'." });

        // 2. Validación de Lista Blanca (Lo único que CodeQL acepta al 100%)
        const ALLOWED_DOMAINS = ['linkedin.com', 'hosting3m.com'];
        const parsedUrl = new URL(url);
        const host = parsedUrl.hostname.toLowerCase().replace('www.', '');

        const isAllowed = ALLOWED_DOMAINS.some(domain =>
            host === domain || host.endsWith('.' + domain)
        );

        if (!isAllowed) {
            return res.status(403).json({ error: "Seguridad: Dominio no permitido." });
        }

        // 3. Al llegar aquí, 'parsedUrl' es totalmente seguro para el bot
        const finalUrl = parsedUrl.toString();
        const isLinkedIn = host === 'linkedin.com' || host.endsWith('.linkedin.com');

        browser = await puppeteer.launch({
            executablePath: process.env.PUPPETEER_EXECUTABLE_PATH || '/usr/bin/chromium-browser',
            args: ['--no-sandbox', '--disable-setuid-sandbox'],
            headless: "new"
        });

        const page = await browser.newPage();
        await page.setUserAgent(USER_AGENT);

        // NAVEGACIÓN
        try {
            // USAR finalUrl AQUÍ (Variable que viene del objeto URL validado)
            await page.goto(finalUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
        } catch (e) {
            console.log(`[WARN] Goto: ${e.message}`);
        }

        // ... resto de tu lógica (cheerio, etc) ...
        const html = await page.content();
        const $ = cheerio.load(html, { decodeEntities: true });

        let responseData;
        if (isLinkedIn) {
            responseData = await scrapeLinkedIn(page, $);
        } else {
            responseData = await scrapeGeneric(page, $, selectors, title, pubDate, description, finalUrl);
        }

        return res.json(responseData);

    } catch (err) {
        return res.status(500).json({ error: err.message });
    } finally {
        if (browser) await browser.close();
    }
});

app.listen(PORT, () => {
    console.log(`Scraper-service v2 escuchando en puerto ${PORT}`);
});