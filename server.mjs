import express from 'express';
import dotenv from 'dotenv';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs';

dotenv.config();
const app = express();
const PORT = Number(process.env.API_PORT || 3001);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const sessions = new Map();
const attempts = new Map();
const SESSION_TTL_MS = 8 * 60 * 60 * 1000;
const COOKIE = 'sstreand_admin_session';
app.disable('x-powered-by');
app.use(express.json({ limit: '20kb' }));
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'same-origin');
  next();
});
function parseCookies(header = '') {
  return Object.fromEntries(header.split(';').map(v => v.trim()).filter(Boolean).map(v => {
    const i = v.indexOf('='); return [v.slice(0, i), decodeURIComponent(v.slice(i + 1))];
  }));
}
function getSession(req) {
  const token = parseCookies(req.headers.cookie)[COOKIE];
  if (!token) return null;
  const session = sessions.get(token);
  if (!session || session.expiresAt < Date.now()) { sessions.delete(token); return null; }
  return { token, ...session };
}
function requireAdmin(req, res, next) {
  if (!getSession(req)) return res.status(401).json({ error: 'Admin sign-in required.' });
  next();
}
function safeEqual(a, b) {
  const aa = Buffer.from(String(a)); const bb = Buffer.from(String(b));
  return aa.length === bb.length && crypto.timingSafeEqual(aa, bb);
}
function passwordMatches(password) {
  const salt = process.env.ADMIN_PASSWORD_SALT || '';
  const expected = process.env.ADMIN_PASSWORD_HASH || '';
  if (!salt || !expected || !password) return false;
  const actual = crypto.scryptSync(String(password), salt, 64).toString('hex');
  return safeEqual(actual, expected);
}
app.post('/api/admin/login', (req, res) => {
  const ip = req.ip || req.socket.remoteAddress || 'unknown';
  const now = Date.now();
  const record = attempts.get(ip) || { count: 0, until: now + 15 * 60 * 1000 };
  if (record.until < now) { record.count = 0; record.until = now + 15 * 60 * 1000; }
  if (record.count >= 8) return res.status(429).json({ error: 'Too many attempts. Wait 15 minutes and try again.' });
  const username = String(req.body?.username || '');
  const password = String(req.body?.password || '');
  const expectedUser = process.env.ADMIN_USERNAME || '';
  if (!safeEqual(username, expectedUser) || !passwordMatches(password)) {
    record.count += 1; attempts.set(ip, record);
    return res.status(401).json({ error: 'Incorrect username or password.' });
  }
  attempts.delete(ip);
  const token = crypto.randomBytes(32).toString('hex');
  sessions.set(token, { expiresAt: now + SESSION_TTL_MS });
  const secureFlag = process.env.NODE_ENV === 'production' ? '; Secure' : '';
  res.setHeader('Set-Cookie', `${COOKIE}=${encodeURIComponent(token)}; HttpOnly; SameSite=Strict; Path=/; Max-Age=${SESSION_TTL_MS / 1000}${secureFlag}`);
  return res.json({ authenticated: true, username: expectedUser });
});
app.get('/api/admin/me', (req, res) => {
  const session = getSession(req);
  if (!session) return res.status(401).json({ authenticated: false });
  res.json({ authenticated: true, username: process.env.ADMIN_USERNAME });
});
app.post('/api/admin/logout', (req, res) => {
  const session = getSession(req);
  if (session) sessions.delete(session.token);
  res.setHeader('Set-Cookie', `${COOKIE}=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0`);
  res.json({ ok: true });
});
// Admin-only test endpoint: verifies that the session guard is enforced.
app.get('/api/admin/protected-check', requireAdmin, (_req, res) => res.json({ authorized: true }));

const dist = path.join(__dirname, 'dist');
if (fs.existsSync(dist)) {
  app.use(express.static(dist, { index: false }));
  app.get('*', (_req, res) => res.sendFile(path.join(dist, 'index.html')));
} else {
  app.get('/', (_req, res) => res.status(200).send('SSTREAND SHOP authentication API is running. Start Vite for the storefront.'));
}
app.listen(PORT, '127.0.0.1', () => console.log(`SSTREAND auth server running on http://127.0.0.1:${PORT}`));
