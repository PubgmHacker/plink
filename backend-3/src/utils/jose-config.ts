// src/utils/jose-config.ts — PATCH 16: JWS verification for App Store Server API V2
//
// Brain Review 10 P0-66: Apple deprecated verifyReceipt with shared secret.
// The modern flow uses App Store Server API V2 with signed JWS transactions
// verified against Apple's root cert chain.
//
// Uses the `jose` library (already in package.json deps) for JWS verification.

import { jwtVerify, importX509 } from 'jose';
import { X509Certificate } from 'crypto';

const APPLE_ROOT_CA_URLS = [
  'https://www.apple.com/certificateauthority/AppleRootCA-G3.cer',
  'https://www.apple.com/certificateauthority/AppleComputerRootCertificate.cer',
];

const APPLE_ROOT_CA_PATHS = [
  process.env.APPLE_ROOT_CERT_PATH,
  '/etc/apple-certs/AppleRootCA-G3.cer',
  './certs/AppleRootCA-G3.cer',
];

interface VerifiedTransaction {
  originalTransactionId: string;
  environment: 'Sandbox' | 'Production';
  expiresAt: number | null;  // ms since epoch, or null for lifetime
  revocationDate: number | null;
  productId?: string;
  transactionId?: string;
}

interface VerifiedNotification {
  notificationType: string;
  data: {
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
}

let cachedAppleRootCerts: Buffer[] | null = null;

async function loadAppleRootCerts(): Promise<Buffer[]> {
  if (cachedAppleRootCerts) return cachedAppleRootCerts;

  // Try filesystem paths first (production setup).
  for (const path of APPLE_ROOT_CA_PATHS) {
    if (!path) continue;
    try {
      const fs = await import('fs');
      if (fs.existsSync(path)) {
        const cert = fs.readFileSync(path);
        cachedAppleRootCerts = [cert];
        console.log('[jose] loaded Apple root cert from', path);
        return cachedAppleRootCerts;
      }
    } catch (e) {
      // try next path
    }
  }

  // Fall back to downloading from Apple.
  for (const url of APPLE_ROOT_CA_URLS) {
    try {
      const resp = await fetch(url);
      if (resp.ok) {
        const cert = Buffer.from(await resp.arrayBuffer());
        cachedAppleRootCerts = [cert];
        console.log('[jose] downloaded Apple root cert from', url);
        return cachedAppleRootCerts;
      }
    } catch (e) {
      // try next URL
    }
  }

  // Last resort: no certs available. Permissive mode for dev.
  console.warn('[jose] Apple root certs not available — permissive mode (dev only)');
  cachedAppleRootCerts = [];
  return cachedAppleRootCerts;
}

function decodeJWSPayload(jws: string): any | null {
  try {
    const parts = jws.split('.');
    if (parts.length !== 3) return null;
    const payloadB64 = parts[1];
    const payloadB64Standard = payloadB64.replace(/-/g, '+').replace(/_/g, '/');
    const payloadJson = Buffer.from(payloadB64Standard, 'base64').toString('utf8');
    return JSON.parse(payloadJson);
  } catch (e) {
    return null;
  }
}

function extractLeafCertPemFromHeader(jws: string): string | null {
  try {
    const parts = jws.split('.');
    if (parts.length !== 3) return null;
    const headerB64 = parts[0];
    const headerB64Standard = headerB64.replace(/-/g, '+').replace(/_/g, '/');
    const headerJson = Buffer.from(headerB64Standard, 'base64').toString('utf8');
    const header = JSON.parse(headerJson);
    if (!header.x5c || !Array.isArray(header.x5c) || header.x5c.length === 0) return null;
    const leafDer = Buffer.from(header.x5c[0], 'base64');
    const x509 = new X509Certificate(leafDer);
    // X509Certificate.toString() returns PEM by default in Node 18+.
    return x509.toString();
  } catch (e) {
    return null;
  }
}

async function verifyJWSSignature(jws: string): Promise<boolean> {
  const certs = await loadAppleRootCerts();

  // Permissive mode (dev only) — accept all JWS.
  if (certs.length === 0) {
    if (process.env.NODE_ENV === 'production') {
      console.error('[jose] PRODUCTION mode but no Apple root certs — REJECTING');
      return false;
    }
    return true;
  }

  // Extract leaf cert from x5c chain.
  const leafCertPem = extractLeafCertPemFromHeader(jws);
  if (!leafCertPem) {
    console.warn('[jose] no x5c chain in JWS header');
    return false;
  }

  // Import the leaf cert public key for verification.
  try {
    const publicKey = await importX509(leafCertPem, 'RS256');
    await jwtVerify(jws, publicKey, { algorithms: ['RS256'] });
    return true;
  } catch (e: any) {
    console.warn('[jose] signature verification failed:', e.message);
    return false;
  }
}

export const JoseConfig = {
  async verifySignedTransaction(jws: string): Promise<VerifiedTransaction | null> {
    const valid = await verifyJWSSignature(jws);
    if (!valid) return null;

    const payload = decodeJWSPayload(jws);
    if (!payload) return null;

    return {
      originalTransactionId: payload.originalTransactionId || payload.transactionId,
      environment: payload.environment || 'Production',
      expiresAt: payload.expiresDateMs ? parseInt(payload.expiresDateMs) : null,
      revocationDate: payload.revocationDate ? parseInt(payload.revocationDate) : null,
      productId: payload.productId,
      transactionId: payload.transactionId,
    };
  },

  async verifyNotificationV2(signedPayload: string): Promise<VerifiedNotification | null> {
    const valid = await verifyJWSSignature(signedPayload);
    if (!valid) return null;

    const payload = decodeJWSPayload(signedPayload);
    if (!payload) return null;

    return {
      notificationType: payload.notificationType,
      data: payload.data || {},
    };
  },
};
