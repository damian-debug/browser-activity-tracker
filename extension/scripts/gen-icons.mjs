// Generates minimal PNG icons using raw PNG encoding (no canvas needed)
// Run: node scripts/gen-icons.mjs

import { writeFileSync } from "fs";
import { createHash } from "crypto";

function createPNG(size) {
  // Draw a simple clock icon: blue circle with hands
  const pixels = new Uint8Array(size * size * 4);

  const cx = size / 2;
  const cy = size / 2;
  const r = size / 2 - 1;

  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const dx = x - cx;
      const dy = y - cy;
      const dist = Math.sqrt(dx * dx + dy * dy);
      const i = (y * size + x) * 4;

      if (dist <= r) {
        // Circle fill: blue
        pixels[i] = 37;
        pixels[i + 1] = 99;
        pixels[i + 2] = 235;
        pixels[i + 3] = 255;
      } else {
        // Transparent
        pixels[i + 3] = 0;
      }

      // Clock hands: white lines
      const hourAngle = -Math.PI / 2 + Math.PI / 3; // 2 o'clock
      const minAngle = -Math.PI / 2 + Math.PI;       // 6 o'clock

      const hourLen = r * 0.5;
      const minLen = r * 0.7;
      const thickness = Math.max(1, size / 16);

      const onHour = isOnLine(dx, dy, 0, 0, Math.cos(hourAngle) * hourLen, Math.sin(hourAngle) * hourLen, thickness);
      const onMin  = isOnLine(dx, dy, 0, 0, Math.cos(minAngle)  * minLen,  Math.sin(minAngle)  * minLen,  thickness);

      if (dist <= r && (onHour || onMin)) {
        pixels[i] = 255;
        pixels[i + 1] = 255;
        pixels[i + 2] = 255;
        pixels[i + 3] = 255;
      }
    }
  }

  return encodePNG(pixels, size, size);
}

function isOnLine(px, py, x1, y1, x2, y2, thickness) {
  const dx = x2 - x1, dy = y2 - y1;
  const len = Math.sqrt(dx * dx + dy * dy);
  if (len === 0) return false;
  const t = Math.max(0, Math.min(1, ((px - x1) * dx + (py - y1) * dy) / (len * len)));
  const cx = x1 + t * dx, cy = y1 + t * dy;
  return Math.sqrt((px - cx) ** 2 + (py - cy) ** 2) <= thickness;
}

function encodePNG(pixels, width, height) {
  const chunks = [];

  // PNG signature
  chunks.push(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));

  // IHDR
  chunks.push(makeChunk("IHDR", Buffer.from([
    (width >> 24) & 0xff, (width >> 16) & 0xff, (width >> 8) & 0xff, width & 0xff,
    (height >> 24) & 0xff, (height >> 16) & 0xff, (height >> 8) & 0xff, height & 0xff,
    8, // bit depth
    2, // color type: RGB (we'll use RGBA = 6)
    0, 0, 0,
  ])));

  // Re-encode as RGBA (color type 6)
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;   // bit depth
  ihdr[9] = 6;   // RGBA
  ihdr[10] = 0;  // compression
  ihdr[11] = 0;  // filter
  ihdr[12] = 0;  // interlace
  chunks.length = 1; // reset, keep only signature
  chunks.push(makeChunk("IHDR", ihdr));

  // IDAT — raw RGBA with filter byte 0 per scanline
  const scanlines = [];
  for (let y = 0; y < height; y++) {
    scanlines.push(0); // filter type None
    for (let x = 0; x < width; x++) {
      const i = (y * width + x) * 4;
      scanlines.push(pixels[i], pixels[i+1], pixels[i+2], pixels[i+3]);
    }
  }
  const raw = Buffer.from(scanlines);
  const compressed = deflate(raw);
  chunks.push(makeChunk("IDAT", compressed));

  // IEND
  chunks.push(makeChunk("IEND", Buffer.alloc(0)));

  return Buffer.concat(chunks);
}

function makeChunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeB = Buffer.from(type, "ascii");
  const crcInput = Buffer.concat([typeB, data]);
  const crc = crc32(crcInput);
  const crcB = Buffer.alloc(4);
  crcB.writeUInt32BE(crc >>> 0, 0);
  return Buffer.concat([len, typeB, data, crcB]);
}

function crc32(buf) {
  let crc = 0xffffffff;
  const table = makeCRCTable();
  for (let i = 0; i < buf.length; i++) {
    crc = table[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  }
  return crc ^ 0xffffffff;
}

function makeCRCTable() {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
}

// Minimal zlib deflate using Node's built-in zlib
import { deflateSync } from "zlib";
function deflate(buf) {
  return deflateSync(buf);
}

for (const size of [16, 48, 128]) {
  const png = createPNG(size);
  writeFileSync(`public/icons/${size}.png`, png);
  console.log(`Generated public/icons/${size}.png`);
}
