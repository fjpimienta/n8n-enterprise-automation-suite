using System;
using System.IO;
using Org.BouncyCastle.Crypto;
using Org.BouncyCastle.X509;
using Org.BouncyCastle.Asn1.Pkcs;
using Org.BouncyCastle.Security;
using iText.Kernel.Pdf;
using iText.Signatures;

// Namespaces del Adaptador iText 9
using iText.Commons.Bouncycastle.Cert;
using iText.Commons.Bouncycastle.Crypto;
using iText.Bouncycastle.Cert;
using iText.Bouncycastle.Crypto;
using iText.Bouncycastle.X509; // <-- EL NAMESPACE QUE FALTABA

namespace FeaSignerAPI.Services
{
    public static class SatSignerService
    {
        public static byte[] SignPAdES(MemoryStream pdfStream, MemoryStream cerStream, MemoryStream keyStream, string password)
        {
            // 1. Extraer el Certificado Público nativo de BC (.cer)
            X509CertificateParser certParser = new X509CertificateParser();
            Org.BouncyCastle.X509.X509Certificate satCertificate = certParser.ReadCertificate(cerStream);

            // 2. Extraer y Desencriptar la Llave Privada nativa de BC (.key)
            AsymmetricKeyParameter privateKey;
            try
            {
                EncryptedPrivateKeyInfo encPrivKeyInfo = EncryptedPrivateKeyInfo.GetInstance(keyStream.ToArray());
                privateKey = PrivateKeyFactory.DecryptKey(password.ToCharArray(), encPrivKeyInfo);
            }
            catch (Exception ex)
            {
                throw new Exception("Contraseña incorrecta o archivo .key corrupto/no soportado.", ex);
            }

            // 3. Preparar iText9 para la inyección de la firma
            using var destStream = new MemoryStream();
            using var pdfReader = new PdfReader(pdfStream);

            var properties = new StampingProperties();
            properties.UseAppendMode();

            PdfSigner signer = new PdfSigner(pdfReader, destStream, properties);

            // 4. ADAPTADOR: Envolver los objetos nativos de BC en las interfaces puente de iText 9
            IPrivateKey iTextPrivateKey = new PrivateKeyBC(privateKey);
            IX509Certificate[] iTextChain = { new X509CertificateBC(satCertificate) };

            // 5. Crear la firma (Usamos "SHA256" directamente como string)
            IExternalSignature pks = new PrivateKeySignature(iTextPrivateKey, "SHA256");

            // 6. Inyectar la firma criptográfica en el PDF (Firma PAdES Invisible)
            signer.SignDetached(pks, iTextChain, null, null, null, 0, PdfSigner.CryptoStandard.CMS);

            return destStream.ToArray();
        }
    }
}