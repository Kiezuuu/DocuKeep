import { generateKeyPairSync } from 'node:crypto';
const { publicKey, privateKey } = generateKeyPairSync('ed25519');
const pub = publicKey.export({ format: 'der', type: 'spki' });
const rawPublic = pub.subarray(pub.length - 32);
console.log('\nPRIVATE_JWK (set as Supabase secret; DO NOT COMMIT):\n' + JSON.stringify(privateKey.export({ format: 'jwk' })));
console.log('\nPUBLIC_KEY_BASE64 (safe to place in index.html):\n' + rawPublic.toString('base64'));
