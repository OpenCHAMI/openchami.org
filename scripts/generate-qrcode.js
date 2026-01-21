#!/usr/bin/env node

/**
 * Generate a QR code as a transparent PNG
 * Usage: node scripts/generate-qrcode.js <url> [output-file]
 * 
 * Examples:
 *   node scripts/generate-qrcode.js "https://openchami.org/docs/getting-started/" qr-getting-started.png
 *   node scripts/generate-qrcode.js "https://openchami.org"
 */

const QRCode = require('qrcode');
const path = require('path');
const fs = require('fs');

const url = process.argv[2];
const outputFile = process.argv[3] || 'qrcode.png';

if (!url) {
  console.error('Usage: node scripts/generate-qrcode.js <url> [output-file]');
  console.error('Example: node scripts/generate-qrcode.js "https://openchami.org/docs/getting-started/" qr-getting-started.png');
  process.exit(1);
}

// Ensure output directory exists
const outputDir = path.dirname(outputFile);
if (!fs.existsSync(outputDir) && outputDir !== '.') {
  fs.mkdirSync(outputDir, { recursive: true });
}

const options = {
  errorCorrectionLevel: 'H',
  type: 'image/png',
  quality: 0.95,
  margin: 1,
  width: 300,
  color: {
    dark: '#000000',
    light: '#FFFFFF'
  }
};

QRCode.toFile(outputFile, url, options, (err) => {
  if (err) {
    console.error('Error generating QR code:', err);
    process.exit(1);
  }
  console.log(`✓ QR code generated: ${outputFile}`);
  console.log(`  URL: ${url}`);
  console.log(`  Size: 300x300 pixels`);
});
