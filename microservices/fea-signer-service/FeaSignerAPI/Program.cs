using FeaSignerAPI.Services;
using Microsoft.AspNetCore.Mvc;
using System.IO;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddOpenApi();
var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

// --- ENDPOINT CRÍTICO DE SELLADO INTERNO ---
app.MapPost("/api/sign/internal", async ([FromForm] IFormFile pdf) =>
{
    // 1. Validación de Entrada (Solo pedimos el PDF)
    if (pdf == null)
    {
        return Results.BadRequest(new { error = "Payload incompleto. Se requiere únicamente el archivo pdf." });
    }

    // 2. Extracción segura de secretos (Variables de Entorno)
    string cerPath = Environment.GetEnvironmentVariable("FIEL_CER_PATH") ?? "/app/certs/csd.cer";
    string keyPath = Environment.GetEnvironmentVariable("FIEL_KEY_PATH") ?? "/app/certs/csd.key";
    string password = Environment.GetEnvironmentVariable("FIEL_PASSWORD");

    // Validar que la infraestructura esté correctamente montada
    if (string.IsNullOrEmpty(password) || !File.Exists(cerPath) || !File.Exists(keyPath))
    {
        return Results.Problem("Error SecOps: Certificados o contraseña no encontrados en el contenedor.", statusCode: 500);
    }

    using var pdfStream = new MemoryStream();
    await pdf.CopyToAsync(pdfStream);

    try
    {
        // 3. Cargar secretos físicos a la memoria RAM
        byte[] cerBytes = await File.ReadAllBytesAsync(cerPath);
        byte[] keyBytes = await File.ReadAllBytesAsync(keyPath);

        using var cerStream = new MemoryStream(cerBytes);
        using var keyStream = new MemoryStream(keyBytes);

        pdfStream.Position = 0;

        // 4. Ejecutar Motor Criptográfico
        byte[] signedPdfBytes = SatSignerService.SignPAdES(pdfStream, cerStream, keyStream, password);

        // Devolver documento sellado
        return Results.File(signedPdfBytes, "application/pdf", $"sellado_{pdf.FileName}");
    }
    catch (Exception ex)
    {
        return Results.Problem(detail: ex.Message, title: "Error Criptográfico Interno");
    }
    finally
    {
        // 5. Destruir variables sensibles de la memoria
        GC.Collect();
    }
})
.DisableAntiforgery();

app.Run();