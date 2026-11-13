// encrypt_disk.mjs — chiffre une image disque pour le chargement automatique par code de licence.
// Usage : node encrypt_disk.mjs DISQUE.st [CODE]   (sans CODE : un code est tiré au hasard)
// Produit stuntcar.st.enc à côté du script appelant (dossier courant) et affiche le code.
// Le fichier chiffré ne sert à rien sans le code : PBKDF2-SHA256 (250 000 tours) + AES-256-GCM.
// Format : "SCRE1" | sel (16 octets) | IV (12 octets) | données chiffrées (avec l'étiquette GCM).
import { readFileSync, writeFileSync } from 'node:fs';
import { webcrypto as crypto } from 'node:crypto';

const [disk, given] = process.argv.slice(2);
if (!disk) { console.error('usage : node encrypt_disk.mjs DISQUE.st [CODE]'); process.exit(1); }
const ALPHA = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';   // sans 0/O ni 1/I
const code = given || Array.from(crypto.getRandomValues(new Uint8Array(20)), (b) => ALPHA[b % 32]).join('').replace(/(.{4})(?!$)/g, '$1-');
const norm = code.toUpperCase().replace(/[^A-Z0-9]/g, '');
if (norm.length < 16) { console.error('code trop court (16 caractères au moins)'); process.exit(1); }

const data = readFileSync(disk);
const salt = crypto.getRandomValues(new Uint8Array(16)), iv = crypto.getRandomValues(new Uint8Array(12));
const base = await crypto.subtle.importKey('raw', new TextEncoder().encode(norm), 'PBKDF2', false, ['deriveKey']);
const key = await crypto.subtle.deriveKey({ name: 'PBKDF2', salt, iterations: 250000, hash: 'SHA-256' }, base,
  { name: 'AES-GCM', length: 256 }, false, ['encrypt']);
const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, data));
writeFileSync('stuntcar.st.enc', Buffer.concat([Buffer.from('SCRE1'), salt, iv, ct]));
console.log('stuntcar.st.enc écrit (' + (ct.length + 33) + ' octets)');
console.log('code de licence : ' + code);
