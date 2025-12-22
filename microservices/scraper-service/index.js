require('./init-webapi');

const express = require('express');
const bodyParser = require('body-parser');
const cheerio = require('cheerio');
const puppeteer = require('puppeteer');
const { PORT, USER_AGENT } = require('./config');

const app = express();
app.use(bodyParser.json());

// --- Funciones de scraping especializadas ---

// Función para scraping GENÉRICO (URL no-LinkedIn o uso anterior)
async function scrapeGeneric(page, $, selectors, title, pubDate, description, finalUrl) {
    const finalResult = {};

    // Iteramos sobre CADA selector (articles, profileMeta, etc.) que se haya enviado
    for (const selectorKey in selectors) {
        const currentSelector = selectors[selectorKey];

        if (!currentSelector || !currentSelector.data) {
            console.log(`[WARN] Selector '${selectorKey}' no tiene propiedad 'data' y fue ignorado.`);
            continue;
        }

        const dataSelectors = currentSelector.data;
        const extractedData = {};

        // Buscamos en el documento por cada selector
        for (const key in dataSelectors) {
            const sel = dataSelectors[key];
            const element = $(sel.selector); 

            let foundValue = null;
            if (sel.attr) {
                foundValue = element.attr(sel.attr);
            } else {
                foundValue = element.text().trim();
            }

            if (foundValue) {
                console.log(`[DEBUG] Encontrado ${key}: ${foundValue.substring(0, 50)}...`);
                extractedData[key] = foundValue;
            }
        }
        // Almacenamos el resultado bajo la clave del selector
        finalResult[selectorKey] = [extractedData]; 
    }

    return {
        status: 200,
        success: Object.keys(finalResult).length > 0,
        url: finalUrl,
        title: title,
        pubDate: pubDate,
        description: description,
        data: finalResult
    };
}

// Función especializada para LinkedIn (Prioriza metadatos y evita el DOM pesado)
async function scrapeLinkedIn(page, $) {
    // LinkedIn es muy difícil de scrapear del DOM, nos enfocamos en los metadatos OpenGraph (OG).
    console.log("[DEBUG] Usando lógica especializada para LinkedIn.");

    const ogTitle = $('meta[property="og:title"]').attr('content');
    const ogDescription = $('meta[property="og:description"]').attr('content');
    const ogImage = $('meta[property="og:image"]').attr('content');

    // Aquí puedes añadir más lógica específica si encuentras selectores estables.

    const result = {
        metaData: [{
            og_title: ogTitle,
            og_description: ogDescription,
            og_image: ogImage
        }]
    };

    return {
        status: 200,
        success: !!ogImage, // Éxito si encontramos al menos la imagen
        url: page.url(),
        title: ogTitle,
        description: ogDescription,
        data: result
    };
}

// --- Rutas de Express ---
app.post('/scrape', async (req, res) => {
 let browser = null;
 try {
  const { url, selectors, title, pubDate, description } = req.body;
  console.log(`[DEBUG] url: ${url}`);
  console.log(`[DEBUG] title: ${title}`);
  console.log(`[DEBUG] description: ${description}`);

  if (!url) {
   return res.status(400).json({ error: "Se requiere 'url'." });
  }

    const isLinkedIn = url.includes('linkedin.com'); // Simplificado para que incluya todos los enlaces de LinkedIn

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

  // Bloqueo de recursos (Imágenes, CSS, etc.) para velocidad
  await page.setRequestInterception(true);
  page.on('request', (req) => {
   const resourceType = req.resourceType();
   if (['image', 'stylesheet', 'font', 'media'].includes(resourceType)) {
    req.abort();
   } else {
    req.continue();
   }
  });

  await page.setUserAgent(USER_AGENT);
  await page.setViewport({ width: 1280, height: 800 });

  console.log(`[DEBUG] Navegando a: ${url}`);
  try {
    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });
  } catch (e) {
    console.log(`[WARN] Timeout en goto inicial: ${e.message}`);
  }

  // Pausa para renderizado JS
  await new Promise(r => setTimeout(r, 8000));
 
  const html = await page.content();
  const $ = cheerio.load(html, { decodeEntities: true });

    let responseData;

    if (isLinkedIn) {
        // Ejecuta la lógica especializada
        responseData = await scrapeLinkedIn(page, $);
    } else if (selectors) {
        // Ejecuta la lógica genérica si se proporcionan selectores
        responseData = await scrapeGeneric(page, $, selectors, title, pubDate, description, page.url());
    } else {
        // Opción de retorno si no es LinkedIn y no hay selectores (solo metadatos básicos)
        responseData = {
            status: 200,
            success: true,
            url: page.url(),
            data: {}
        };
    }

  return res.json(responseData);

 } catch (err) {
  console.error("[ERROR] Scraping:", err);
  return res.status(500).json({ error: err.message, stack: err.stack });
 } finally {
  if (browser) {
    try { await browser.close(); } catch(e) { console.error(e); }
  }
 }
});

app.listen(PORT, () => {
 console.log(`Scraper-service v2 escuchando en puerto ${PORT}`);
});
