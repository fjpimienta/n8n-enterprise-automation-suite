require('./init-webapi');

const express = require('express');
const bodyParser = require('body-parser');
const cheerio = require('cheerio');
const puppeteer = require('puppeteer');
const ipaddr = require('ipaddr.js');
const { URL } = require('url');
const { PORT, USER_AGENT } = require('./config');
const axios = require('axios');

const app = express();
app.use(bodyParser.json());

// --- FUNCIONES DE SEGURIDAD Y HELPERS ---

function isSafeUrl(urlInput) {
    try {
        const parsed = new URL(urlInput);
        if (!['http:', 'https:'].includes(parsed.protocol)) return false;
        const hostname = parsed.hostname;
        const lowerHost = hostname.toLowerCase();
        const forbiddenHosts = ['localhost', '127.0.0.1', '::1', '0.0.0.0', 'metadata.google.internal', '169.254.169.254', 'instance-data'];
        if (forbiddenHosts.includes(lowerHost)) return false;
        if (ipaddr.isValid(hostname)) {
            const addr = ipaddr.parse(hostname);
            const range = addr.range();
            const forbiddenRanges = ['unspecified', 'loopback', 'linkLocal', 'multicast', 'private', 'reserved', 'uniqueLocal', 'carrierGradeNat'];
            if (forbiddenRanges.includes(range)) return false;
        }
        return true;
    } catch (e) { return false; }
}

async function clickByText(page, text) {
    const found = await page.evaluate((textToFind) => {
        const elements = [...document.querySelectorAll('a, button, span, div, h4')];
        const el = elements.find(element => element.innerText.includes(textToFind));
        if (el) { el.click(); return true; }
        return false;
    }, text);
    return found;
}

// --- FUNCIÓN SOLVER REFINADA (Para evitar rechazos de OpenAI) ---
async function solveImssCaptcha(page, openai_key, captchaImgSelector, inputSelector) {
    try {
        const captchaElement = await page.waitForSelector(captchaImgSelector, { visible: true, timeout: 10000 });
        await new Promise(r => setTimeout(r, 800));
        const imageBuffer = await captchaElement.screenshot({ encoding: 'base64' });

        const gptResponse = await axios.post('https://api.openai.com/v1/chat/completions', {
            model: "gpt-4o",
            messages: [
                {
                    role: "user",
                    content: [
                        { type: "text", text: "OCR Task: Extract the alphanumeric characters from this distorted image. Provide ONLY the characters. No conversation, no apologies." },
                        { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageBuffer}` } }
                    ]
                }
            ],
            temperature: 0.0,
            max_tokens: 15
        }, {
            headers: { 'Authorization': `Bearer ${openai_key}` }
        });

        let solution = gptResponse.data.choices[0].message.content.trim().replace(/[^a-zA-Z0-9]/g, '');
        
        // Si OpenAI responde con su mensaje de "I'm sorry", forzamos el error para que el bucle reintente
        if (solution.length > 15 || solution.toLowerCase().includes('sorry')) {
            throw new Error("OpenAI se negó a resolver el captcha");
        }

        console.log(`[IMSS] Captcha procesado: ${solution}`);
        await page.click(inputSelector, { clickCount: 3 });
        await page.keyboard.press('Backspace');
        await page.type(inputSelector, solution, { delay: 100 });

        return true;
    } catch (e) {
        console.error(`[IMSS] Error en solver: ${e.message}`);
        return false;
    }
}

// --- ENDPOINT 1: AUTOMATIZACIÓN IMSS (CORREGIDO) ---
// --- ENDPOINT 1: AUTOMATIZACIÓN IMSS (COMPLETO Y SIN ERRORES DE REFERENCIA) ---
app.post('/automate/quoted-weeks', async (req, res) => {
    const { curp, nss, email, openai_key } = req.body;
    let browser = null;

    if (!curp || !nss || !email) return res.status(400).json({ error: "Faltan datos (CURP, NSS, Email)." });

    // Definición de selectores (Movido aquí para que sea global al endpoint)
    const selectors = {
        curp: '#CURP',
        nss: '#NSS',
        email: '#Correo',
        emailConfirm: '#CorreoConfirma',
        captchaImg: '#captchaImg',
        captchaInput: '#captcha',
        btnSubmit: '#btnContinuar' // ID correcto según tu HTML
    };

    try {
        console.log(`[IMSS] Iniciando proceso para: ${email}`);

        browser = await puppeteer.launch({
            executablePath: '/usr/bin/chromium-browser',
            args: [
                '--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage',
                '--disable-gpu', '--no-zygote', '--hide-scrollbars', '--mute-audio'
            ],
            headless: "new",
            protocolTimeout: 60000,
        });

        const page = await browser.newPage();
        await page.setUserAgent(USER_AGENT);
        await page.setViewport({ width: 1280, height: 800 });

        // --- FASE 1: LOGIN CON REINTENTOS ---
        let loggedIn = false;
        const maxAttempts = 3;

        for (let attempt = 1; attempt <= maxAttempts; attempt++) {
            console.log(`[IMSS] Intento de Login ${attempt} de ${maxAttempts}...`);

            await page.goto('https://serviciosdigitales.imss.gob.mx/semanascotizadas-web/usuarios/IngresoAsegurado', {
                waitUntil: 'networkidle2',
                timeout: 45000
            });

            await page.waitForSelector(selectors.curp, { visible: true });

            // Llenar campos con limpieza previa
            await page.click(selectors.curp, { clickCount: 3 });
            await page.type(selectors.curp, curp);
            await page.type(selectors.nss, nss);

            await page.click(selectors.email, { clickCount: 3 });
            await page.type(selectors.email, email);
            await page.type(selectors.emailConfirm, email);

            // Resolver Captcha
            await solveImssCaptcha(page, openai_key, selectors.captchaImg, selectors.captchaInput);

            console.log("[IMSS] Haciendo clic en el botón de ingresar...");
            await Promise.all([
                page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 15000 }).catch(() => { }),
                page.click(selectors.btnSubmit),
            ]);

            // Validación de éxito
            const currentUrl = page.url();
            const content = await page.content();

            if (currentUrl.includes('Menu') || content.includes('Constancia de Semanas Cotizadas')) {
                console.log("[IMSS] Login exitoso.");
                loggedIn = true;
                break;
            } else {
                console.log(`[IMSS] Intento ${attempt} fallido. Revisando si hay mensajes de error...`);
                // Pequeña espera por si el DOM se actualiza con "Captcha incorrecto"
                await new Promise(r => setTimeout(r, 1000));
            }
        }

        if (!loggedIn) {
            throw new Error("No se pudo iniciar sesión tras 3 intentos (Captcha persistente o datos inválidos).");
        }

        // --- FASE 2: NAVEGACIÓN A CONFIGURACIÓN ---
        console.log("[IMSS] Navegando a solicitud de constancia...");

        // El botón del Dashboard para entrar
        const btnReporteSelector = 'button[name="reporte"]';
        await page.waitForSelector(btnReporteSelector, { visible: true, timeout: 15000 });

        await Promise.all([
            page.waitForNavigation({ waitUntil: 'networkidle2' }),
            page.click(btnReporteSelector),
        ]);

        // Marcar "Reporte detallado"
        try {
            await page.waitForSelector('#detalle', { visible: true, timeout: 8000 });
            await page.click('#detalle');
            console.log("[IMSS] Reporte detallado marcado.");
        } catch (e) {
            console.log("[WARN] Checkbox #detalle no encontrado, continuando...");
        }

        // --- FASE 3: SEGUNDO CAPTCHA Y ENVÍO FINAL ---
        console.log("[IMSS] Resolviendo segundo captcha en página de detalle...");

        // Resolver el captcha que está arriba del botón Continuar final
        await solveImssCaptcha(page, openai_key, selectors.captchaImg, selectors.captchaInput);

        console.log("[IMSS] Haciendo clic en Continuar final...");
        await page.click('#btnContinuar');

        // Manejo de Modal de Confirmación (Si aparece)
        await new Promise(r => setTimeout(r, 2500));
        const buttons = await page.$$('button');
        for (const btn of buttons) {
            const text = await page.evaluate(el => el.innerText, btn);
            if (text.match(/(Aceptar|Solicitar|Continuar)/i)) {
                await btn.click().catch(() => { });
                console.log(`[IMSS] Confirmación modal clickeada: ${text}`);
                break;
            }
        }

        // --- FASE FINAL: ESPERAR ÉXITO ---
        console.log("[IMSS] Esperando confirmación de envío por parte del IMSS...");
        try {
            await page.waitForFunction(
                () => {
                    const t = document.body.innerText.toLowerCase();
                    return t.includes("enviado") || t.includes("exitosamente") || t.includes("revisa tu correo");
                },
                { timeout: 30000 }
            );

            const successMsg = await page.evaluate(() => document.body.innerText);
            return res.json({
                status: "success",
                message: "Proceso completado con éxito.",
                details: successMsg.substring(0, 250)
            });

        } catch (e) {
            console.log("[WARN] Timeout esperando texto de éxito. Verificando estado final...");
            const finalContent = await page.evaluate(() => document.body.innerText);
            return res.json({
                status: "uncertain",
                message: "No se detectó el mensaje de éxito, pero se completaron los pasos.",
                details: finalContent.substring(0, 200)
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

// --- ENDPOINT 2: SCRAPER GENÉRICO ---
app.post('/scrape', async (req, res) => {
    let browser = null;
    try {
        const { url, selectors, title, pubDate, description } = req.body;
        if (!url) return res.status(400).json({ error: "Se requiere 'url'." });

        const ALLOWED_DOMAINS = ['linkedin.com', 'hosting3m.com', 'imss.gob.mx'];
        const parsedUrl = new URL(url);
        const host = parsedUrl.hostname.toLowerCase().replace('www.', '');

        const isAllowed = ALLOWED_DOMAINS.some(domain => host === domain || host.endsWith('.' + domain));
        if (!isAllowed) return res.status(403).json({ error: "Seguridad: Dominio no permitido." });

        const finalUrl = parsedUrl.toString();
        const isLinkedIn = host === 'linkedin.com' || host.endsWith('.linkedin.com');

        browser = await puppeteer.launch({
            executablePath: process.env.PUPPETEER_EXECUTABLE_PATH || '/usr/bin/chromium-browser',
            args: ['--no-sandbox', '--disable-setuid-sandbox'],
            headless: "new"
        });

        const page = await browser.newPage();
        await page.setUserAgent(USER_AGENT);

        try {
            await page.goto(finalUrl, { waitUntil: 'domcontentloaded', timeout: 60000 });
        } catch (e) { console.log(`[WARN] Goto: ${e.message}`); }

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

async function scrapeLinkedIn(page, $) {
    // *** PEGA AQUÍ TU LÓGICA DE LINKEDIN ***
    return { error: "Función scrapeLinkedIn no implementada en este archivo completo" };
}

async function scrapeGeneric(page, $, selectors, title, pubDate, description, finalUrl) {
    // *** PEGA AQUÍ TU LÓGICA DE SCRAPE GENERIC ***
    return { title: "Generic Scraper", url: finalUrl };
}

// --- SERVIDOR ---
app.listen(PORT, () => {
    console.log(`Scraper-service v2 escuchando en puerto ${PORT}`);
});