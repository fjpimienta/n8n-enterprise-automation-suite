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
function isSafeUrl(urlInput) {
    try {
        const parsed = new URL(urlInput);

        // 1. Solo permitir protocolos web estándar
        if (!['http:', 'https:'].includes(parsed.protocol)) return false;

        const hostname = parsed.hostname;

        // 2. Bloquear nombres de host prohibidos
        const forbiddenHosts = ['localhost', '127.0.0.1', 'metadata.google.internal'];
        if (forbiddenHosts.includes(hostname.toLowerCase())) return false;

        // 3. Validar si es una IP privada (especialmente útil si pasan la IP directamente)
        if (ipaddr.isValid(hostname)) {
            const addr = ipaddr.parse(hostname);
            const range = addr.range();
            // Bloquea: loopback, private, linklocal, multicast, etc.
            if (range !== 'unicast') return false;
        }

        return true;
    } catch (e) {
        return false; // Si no se puede parsear, no es segura
    }
}

// ... [Tus funciones scrapeGeneric y scrapeLinkedIn se mantienen igual] ...

app.post('/scrape', async (req, res) => {
    let browser = null;
    try {
        const { url, selectors, title, pubDate, description } = req.body;

        if (!url) {
            return res.status(400).json({ error: "Se requiere 'url'." });
        }

        // 1. Parseamos la URL inmediatamente (Evita errores de variable no definida)
        let parsedUrl;
        try {
            parsedUrl = new URL(url);
        } catch (e) {
            return res.status(400).json({ error: "URL inválida." });
        }

        // 2. VALIDACIÓN DE SEGURIDAD SSRF
        if (!isSafeUrl(url)) {
            console.error(`[SECURITY] Intento de SSRF bloqueado para la URL: ${url}`);
            return res.status(403).json({ error: "URL no permitida por razones de seguridad." });
        }

        // 3. VALIDACIÓN SEGURA DE LINKEDIN (Soluciona Alerta #1)
        // Ahora sí, parsedUrl existe y podemos leer su hostname
        const isLinkedIn = parsedUrl.hostname === 'linkedin.com' ||
            parsedUrl.hostname.endsWith('.linkedin.com');

        console.log(`[DEBUG] url: ${url} (isLinkedIn: ${isLinkedIn})`);

        // --- Configuración de Puppeteer ---
        browser = await puppeteer.launch({
            executablePath: process.env.PUPPETEER_EXECUTABLE_PATH || '/usr/bin/chromium-browser',
            args: [
                '--no-sandbox',
                '--disable-setuid-sandbox',
                '--disable-dev-shm-usage',
                '--disable-gpu',
                '--no-zygote',
            ],
            headless: "new",
            protocolTimeout: 180000
        });

        const page = await browser.newPage();

        // Bloqueo de recursos para velocidad
        await page.setRequestInterception(true);
        page.on('request', (req) => {
            if (['image', 'stylesheet', 'font', 'media'].includes(req.resourceType())) {
                req.abort();
            } else {
                req.continue();
            }
        });

        await page.setUserAgent(USER_AGENT);
        await page.setViewport({ width: 1280, height: 800 });

        console.log(`[DEBUG] Navegando a: ${url}`);
        try {
            // Puppeteer ahora solo navega a URLs que pasaron el filtro de isSafeUrl
            await page.goto(parsedUrl.toString(), { waitUntil: 'domcontentloaded', timeout: 60000 });
        } catch (e) {
            console.log(`[WARN] Timeout en goto inicial: ${e.message}`);
        }

        // ... [El resto de tu lógica se mantiene igual] ...
        await new Promise(r => setTimeout(r, 8000));
        const html = await page.content();
        const $ = cheerio.load(html, { decodeEntities: true });

        let responseData;
        if (isLinkedIn) {
            responseData = await scrapeLinkedIn(page, $);
        } else if (selectors) {
            responseData = await scrapeGeneric(page, $, selectors, title, pubDate, description, page.url());
        } else {
            responseData = { status: 200, success: true, url: page.url(), data: {} };
        }

        return res.json(responseData);

    } catch (err) {
        console.error("[ERROR] Scraping:", err);
        return res.status(500).json({ error: err.message });
    } finally {
        if (browser) {
            try { await browser.close(); } catch (e) { console.error(e); }
        }
    }
});

app.listen(PORT, () => {
    console.log(`Scraper-service v2 escuchando en puerto ${PORT}`);
});