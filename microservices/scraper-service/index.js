require('./init-webapi');

const express = require('express');
const bodyParser = require('body-parser');
const cheerio = require('cheerio');
const puppeteer = require('puppeteer');
const ipaddr = require('ipaddr.js'); // Librería de seguridad
const { URL } = require('url');      // Módulo nativo
const { PORT, USER_AGENT } = require('./config');
const axios = require('axios'); // Asegúrate de importarlo arriba

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
async function clickByText(page, text) {
    const found = await page.evaluate((textToFind) => {
        const elements = [...document.querySelectorAll('a, button, span, div, h4')];
        const el = elements.find(element => element.innerText.includes(textToFind));
        if (el) {
            el.click();
            return true;
        }
        return false;
    }, text);
    return found;
}

app.post('/automate/quoted-weeks', async (req, res) => {
    const { curp, nss, email, openai_key } = req.body;
    let browser = null;

    if (!curp || !nss || !email) return res.status(400).json({ error: "Faltan datos (CURP, NSS, Email)." });

    try {
        console.log(`[IMSS] Iniciando proceso para: ${email}`);
        console.log(`[DEBUG] Longitud de la clave recibida: ${openai_key ? openai_key.length : 0}`);
        if (openai_key) {
            console.log(`[DEBUG] Comienzo de la clave: ${openai_key.substring(0, 7)}...`);
        }
        browser = await puppeteer.launch({
            executablePath: '/usr/bin/chromium-browser',
            args: [
                '--no-sandbox',
                '--disable-setuid-sandbox',
                '--disable-dev-shm-usage', // Usa /tmp en lugar de memoria compartida limitada
                '--disable-gpu',
                '--no-zygote',
                '--hide-scrollbars',
                '--mute-audio',
                '--disable-breakpad'       // Evita reportes de crash que consumen recursos
            ],
            headless: "new",
            protocolTimeout: 60000,
        });

        const page = await browser.newPage();
        await page.setUserAgent(USER_AGENT);

        // 1. Ir al sitio del IMSS
        const targetUrl = 'https://serviciosdigitales.imss.gob.mx/semanascotizadas-web/usuarios/IngresoAsegurado';
        await page.goto(targetUrl, { waitUntil: 'networkidle2', timeout: 60000 });
        console.log("[IMSS] Página de login cargada.");

        // Definimos selectores exactos (El IMSS es sensible a mayúsculas/minúsculas)
        const selectors = {
            curp: '#CURP',
            nss: '#NSS',
            email: '#Correo',
            emailConfirm: '#CorreoConfirma', // Verificamos este ID
            captchaImg: '#captchaImg',
            captchaInput: '#captcha',
            btnSubmit: '#btnAceptar, button[type="submit"], .btn-primary'
        };
        console.log("[IMSS] Esperando a que carguen los campos...");

        // Esperamos a que el formulario principal esté visible
        await page.waitForSelector(selectors.curp, { visible: true, timeout: 20000 });

        // Escribimos con pequeños retrasos para simular a un humano y evitar bloqueos
        await page.type(selectors.curp, curp, { delay: 50 });
        await page.type(selectors.nss, nss, { delay: 50 });

        // Esperamos explícitamente al campo de confirmación antes de escribir en él
        await page.waitForSelector(selectors.emailConfirm, { visible: true, timeout: 5000 });

        await page.type(selectors.email, email, { delay: 50 });
        await page.type(selectors.emailConfirm, email, { delay: 50 });

        // 3. Manejo del CAPTCHA con IA
        // Localizar el elemento del captcha
        const captchaElement = await page.$(selectors.captchaImg); // <--- REVISAR SELECTOR REAL
        if (captchaElement) {
            // Tomar screenshot solo del elemento captcha
            const imageBuffer = await captchaElement.screenshot({ encoding: 'base64' });

            // Consultar a OpenAI (GPT-4o) para resolverlo
            const gptResponse = await axios.post('https://api.openai.com/v1/chat/completions', {
                model: "gpt-4o",
                messages: [
                    {
                        role: "user",
                        content: [
                            { type: "text", text: "What are the characters in this captcha image? Return ONLY the characters, no spaces, no text." },
                            { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageBuffer}` } }
                        ]
                    }
                ],
                max_tokens: 10
            }, {
                headers: { 'Authorization': `Bearer ${openai_key}` }
            });

            const captchaSolution = gptResponse.data.choices[0].message.content.trim();
            console.log(`[IMSS] Captcha resuelto: ${captchaSolution}`);

            // Escribir captcha
            await page.type('#captcha', captchaSolution); // <--- REVISAR SELECTOR REAL
        }

        // 4. Enviar Login
        console.log("[IMSS] Haciendo clic en el botón de ingresar...");
        await page.waitForSelector(selectors.btnSubmit, { visible: true, timeout: 30000 });
        await Promise.all([
            page.waitForNavigation({ waitUntil: 'networkidle2' }),
            page.click(selectors.btnSubmit),
        ]);

        // --- VALIDACIÓN DE LOGIN ---
        const pageContent = await page.content();
        if (pageContent.includes("incorrecto") || pageContent.includes("error")) {
            throw new Error("Login fallido: Captcha incorrecto o datos inválidos.");
        }

        /// 5. NAVEGACIÓN INTERNA
        console.log("[IMSS] Login exitoso. Buscando botón de constancia...");

        // Esperamos a que el panel de opciones esté presente
        await page.waitForSelector('button[name="reporte"]', { timeout: 15000 });

        // Paso A: Clic en "Constancia de Semanas Cotizadas en el IMSS"
        // Usamos el selector específico que encontraste
        await Promise.all([
            page.waitForNavigation({ waitUntil: 'networkidle2' }),
            page.click('button[name="reporte"]'),
        ]);

        console.log("[IMSS] Entrando a la configuración del reporte...");

        // Paso B: Seleccionar "Reporte detallado"
        // Este paso suele abrir una pantalla con un checkbox
        try {
            await page.waitForSelector('input[type="checkbox"]', { timeout: 10000 });
            await page.evaluate(() => {
                const checkboxes = document.querySelectorAll('input[type="checkbox"]');
                checkboxes.forEach(cb => {
                    // Marcamos el checkbox (usualmente es el único en esta pantalla)
                    if (!cb.checked) cb.click();
                });
            });
            console.log("[IMSS] Reporte detallado marcado.");
        } catch (e) {
            console.log("[WARN] No se encontró checkbox de reporte detallado o ya estaba marcado.");
        }

        // Paso C: Clic en Continuar (el botón final para que envíen el PDF al correo)
        const finalBtnSelector = 'button[type="submit"].btn-primary, #btnContinuar';
        await page.waitForSelector(finalBtnSelector, { visible: true, timeout: 15000 });

        console.log("[IMSS] Haciendo clic en Continuar final...");

        // Ejecutamos el clic sin Promise.all(waitForNavigation) 
        // porque el IMSS a veces no cambia de URL, solo muestra un mensaje.
        await page.click(finalBtnSelector);

        // 6. Confirmación final
        console.log("[IMSS] Esperando mensaje de confirmación de envío...");

        try {
            // Esperamos a que aparezca texto de éxito en la pantalla
            await page.waitForFunction(
                () => {
                    const text = document.body.innerText.toLowerCase();
                    return text.includes("enviado") ||
                        text.includes("exitosamente") ||
                        text.includes("finalizado") ||
                        text.includes("correo electrónico");
                },
                { timeout: 30000 }
            );

            const successMsg = await page.evaluate(() => document.body.innerText);
            const cleanMsg = successMsg.replace(/\n/g, ' ').substring(0, 300);

            console.log(`[IMSS] Finalizado con éxito.`);
            return res.json({
                status: "success",
                message: "Constancia solicitada correctamente.",
                details: cleanMsg
            });
        } catch (e) {
            console.log("[IMSS] Tiempo de espera de confirmación agotado, verificando pantalla...");
            const currentContent = await page.evaluate(() => document.body.innerText);

            if (currentContent.includes("incorrecto")) {
                throw new Error("El sistema indica un error en los datos o captcha al finalizar.");
            }

            return res.json({
                status: "uncertain",
                message: "Se hizo clic en finalizar pero no se detectó el mensaje de éxito.",
                details: currentContent.substring(0, 200)
            });
        }

    } catch (err) {
        console.error(`[ERROR] ${err.message}`);
        let errorShot = "";
        if (browser) {
            try {
                const pages = await browser.pages();
                if (pages.length > 0) errorShot = await pages[0].screenshot({ encoding: 'base64' });
            } catch (e) { }
        }
        res.status(500).json({ error: err.message, screenshot: errorShot });
    } finally {
        if (browser) await browser.close();
    }
});

app.post('/scrape', async (req, res) => {
    let browser = null;
    try {
        // 1. Usamos 'url' como nombre único para no confundir al bot
        const { url, selectors, title, pubDate, description } = req.body;

        if (!url) return res.status(400).json({ error: "Se requiere 'url'." });

        // 2. Validación de Lista Blanca (Lo único que CodeQL acepta al 100%)
        const ALLOWED_DOMAINS = ['linkedin.com', 'hosting3m.com', 'imss.gob.mx'];
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