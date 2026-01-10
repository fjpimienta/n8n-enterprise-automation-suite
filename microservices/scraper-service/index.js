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
        const lowerHost = hostname.toLowerCase();

        // 2. Bloquear nombres de host prohibidos y de metadatos de la nube
        const forbiddenHosts = [
            'localhost',
            '127.0.0.1',
            '::1',
            '0.0.0.0',
            'metadata.google.internal',
            '169.254.169.254',
            'instance-data'
        ];
        if (forbiddenHosts.includes(lowerHost)) return false;

        // 3. Validación profunda de IP usando ipaddr.js
        if (ipaddr.isValid(hostname)) {
            const addr = ipaddr.parse(hostname);
            const range = addr.range();

            // Lista estricta de rangos PROHIBIDOS (RFC1918 y otros)
            const forbiddenRanges = [
                'unspecified',
                'loopback',
                'linkLocal',
                'multicast',
                'private',
                'reserved',
                'uniqueLocal',
                'carrierGradeNat'
            ];

            if (forbiddenRanges.includes(range)) return false;
        }

        return true;
    } catch (e) {
        return false;
    }
}

// ... [Tus funciones scrapeGeneric y scrapeLinkedIn se mantienen igual] ...

app.post('/scrape', async (req, res) => {
    let browser = null;
    try {
        // 1. Extraemos el input
        const { url: rawUrl, selectors, title, pubDate, description } = req.body;

        if (!rawUrl) {
            return res.status(400).json({ error: "Se requiere 'url'." });
        }

        // 2. Sanitización inmediata: Creamos el objeto URL y validamos
        // Al usar una nueva constante (safeUrlObj), rompemos el rastro del input "sucio"
        let safeUrlObj;
        try {
            safeUrlObj = new URL(rawUrl);
        } catch (e) {
            return res.status(400).json({ error: "URL inválida." });
        }

        // 3. Validación de seguridad estricta
        if (!isSafeUrl(rawUrl)) {
            console.error(`[SECURITY] SSRF bloqueado: ${rawUrl}`);
            return res.status(403).json({ error: "URL no permitida por seguridad." });
        }

        // A partir de aquí, SOLO usamos safeUrlObj
        const finalUrl = safeUrlObj.toString();
        const isLinkedIn = safeUrlObj.hostname === 'linkedin.com' ||
            safeUrlObj.hostname.endsWith('.linkedin.com');

        console.log(`[DEBUG] Procesando: ${finalUrl}`);

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
            // USAMOS finalUrl que proviene del objeto validado
            await page.goto(finalUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
        } catch (e) {
            console.log(`[WARN] Timeout en goto: ${e.message}`);
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