
import { createPrivateKey, createPublicKey } from 'node:crypto';
import { execFileSync } from 'node:child_process';

const expected = 'KagHtN5h3Bosagi6LyweAbuHelUmS2ZO7Tbss1vYS9Q=';

try {
  // Paste your existing private JWK locally when prompted.
  const { createInterface } = await import('node:readline/promises');
  const rl = createInterface({
    input: process.stdin,
    output: process.stdout
  });

  const jwkText = await rl.question('Paste private JWK (input is hidden only if terminal supports it): ');
  rl.close();

  const privateKey = createPrivateKey({
    key: JSON.parse(jwkText),
    format: 'jwk'
  });

  const publicKey = createPublicKey(privateKey);
  const der = publicKey.export({ format: 'der', type: 'spki' });
  const actual = der.subarray(der.length - 32).toString('base64');

  console.log(
    actual === expected
      ? 'MATCH: Private key matches frontend public key.'
      : 'MISMATCH: Private key does not match frontend public key.'
  );
} catch {
  console.log('Verification failed. Check the JWK format.');
}
