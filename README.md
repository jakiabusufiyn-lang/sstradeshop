# SSTREAND SHOP — storefront starter

A responsive React + TypeScript storefront for a Bangladesh-focused fashion, handbags, beauty and skincare shop. This repository includes a polished interactive **demo storefront** plus a Supabase schema and a starter Edge Function. It is **not yet a production-ready, fully integrated commerce system**: the visible cart, wishlist, sample products, demo checkout and demo admin are browser-local. They do not create real orders or authenticate admins. The backend pieces need to be wired in, reviewed and tested before taking real customer orders or money.

## What works in the demo

- Responsive premium storefront with SSTREAND SHOP visual identity, hero, collections, product grid, search and sorting.
- Product cards, local cart and wishlist persisted in browser localStorage.
- Quantity controls and demo stock limits; BDT price display.
- Bangladesh-style demo checkout form with mobile-number validation and COD / manual-payment labels.
- Admin sign-in checked by a local server endpoint (temporary bootstrap credentials); session cookie is HttpOnly and rate-limited.
- Admin demo panel to add sample products and configure manual payment display settings in browser localStorage.
- Basic SEO metadata, accessible labels, reduced-motion support and lazy-loaded product images.
- Customer sign-in/sign-up UI wired to Supabase Auth when project URL and anon key are configured.

## Run locally

Requirements: Node.js 20+ and npm.

```bash
npm install
npm run dev
```

The development command starts the Vite storefront and a local server-side admin authentication API. The ZIP includes a private `.env` file for the temporary local admin login; do not share that file. For Supabase customer accounts, create `.env.local` with only `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` values from your own project. Change admin credentials before sharing or deploying publicly.

Open the local URL Vite prints (usually `http://localhost:5173`). The storefront can run without Supabase in demo mode. Build-check with:

```bash
npm run build
```

## Connect Supabase

1. Create a Supabase project.
2. Install the Supabase CLI and authenticate: `npx supabase login`.
3. From this folder, run `npx supabase link --project-ref YOUR_PROJECT_REF`.
4. Apply schema: `npx supabase db push`.
5. Copy the project URL and **anon/public** key into `.env.local` using the names in `.env.example`.
6. Create a private `product-images` storage bucket. Add policies allowing public reads only if product imagery is intended to be public, and admin-only uploads/updates/deletes. Validate file size and MIME type server-side.
7. Wire the frontend to `@supabase/supabase-js`, replace sample product reads with published database products, and replace local checkout with `supabase.functions.invoke('create-order', ...)`.

Never put `SUPABASE_SERVICE_ROLE_KEY`, payment secrets, OAuth client secrets, or an admin password in `VITE_*` variables or frontend code. Frontend `VITE_*` values are public by design.

### Important backend work before launch

- The SQL migration creates the core tables and RLS policies. Review it with a Supabase/Postgres engineer before production use.
- `create-order` is an illustrative server-side function. Before launch, change order creation to a single Postgres RPC/transaction that locks product rows, validates current price and stock, reserves/decrements inventory atomically, and writes order + items + payment record in one transaction. Add retry-safe idempotency and tests. Do not rely on the demo checkout.
- The function currently uses a service role to perform writes and includes a stock-race warning. It does not decrement inventory; it must not be considered launch-ready.
- Set up admin initialization through a one-time trusted server script or dashboard process: create the auth user, set `profiles.role='admin'` using service-role credentials in a trusted environment, require a password reset, enable MFA where practical, and audit admin actions. Never set admin roles from the public signup flow.
- Review and test RLS using anon, customer A, customer B, and admin accounts. Add rate limits, abuse protection, logging, backups, monitoring, and privacy/retention policies.

## Local admin sign-in

For the included local development build, use username `SSTRADEADMIN` and the temporary password supplied to you by the store owner. The password is stored as a server-side scrypt hash in `.env`, not in frontend JavaScript. Login sessions use an HttpOnly, SameSite cookie, expire after 8 hours, and repeated failed attempts are rate-limited. This is a local-development bootstrap only: change the credentials and use HTTPS plus a production session store before deployment. Product data, orders, and payment settings are still browser-local demo data; this login does not make the shop production-ready.

## Payments in Bangladesh

- **COD:** Can be supported after the order endpoint and order status workflow are fully integrated.
- **bKash / Nagad:** Obtain approved merchant API credentials and use the official provider documentation. Implement server-side payment creation, callback signature/token verification, transaction status verification, replay protection, and reconciliation. Never mark an order paid from a browser-only success redirect.
- **Bank transfer:** Configure real business-owned bank details through a private admin setting and verify transfers manually. No bank account details are included here.
- The checkout labels for bKash/Nagad/bank are placeholders; no payment is currently collected.

## Google / Facebook OAuth

Configure the provider in Supabase Auth, set the exact redirect/callback URLs for local development and production, configure OAuth client IDs/secrets in Supabase, and test sign-in/sign-out/password reset/email verification. No fake social login buttons are included in this starter.

## Media and deployment

- Use Supabase Storage or a dedicated image CDN for production media. Check MIME type, extension, file size, and permissions; don't trust client file names.
- Deploy the frontend to Vercel, Netlify, or another Vite-compatible host. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in that host's environment settings.
- Deploy Edge Functions with `npx supabase functions deploy create-order` after implementation and security review.
- Add a custom domain, HTTPS, production OAuth redirect URLs, sitemap generation, robots rules, analytics consent/privacy choices, error monitoring and backups.

## Current gaps

No live auth, persistent frontend product management, file uploads, real customer accounts, order tracking, actual order submission, transactional inventory reservation, coupon validation, live payment gateway, email/SMS notifications, social OAuth, admin content editor, CSV export, full policy pages, or automated end-to-end tests are connected yet. Sample product images are remote Unsplash images and product details are illustrative; verify sourcing, claims, licensing and stock before publishing.

## Latest demo improvements (2026-10-27)

- The admin demo now includes a **Payment methods** section where the owner can enable/disable COD, bKash manual payment, Nagad manual payment and bank transfer, and enter business payment instructions.
- Enabled manual methods appear in checkout with the configured instructions.
- Demo products and payment-display settings are saved in the current browser's localStorage, so they survive a normal page refresh in that same browser profile.
- These changes are still local demo settings, not shared database settings. They do not collect or verify payments. Do not put personal bank login credentials here. For live bKash/Nagad checkout, use approved merchant API credentials and server-side verification.
- Customer account icon currently points to the required Supabase Auth setup; real sign-up/sign-in and secure admin role validation are not yet connected. Do not use the demo admin panel for a public production store.


## Local admin credentials and security

The temporary local admin username is `SSTRADEADMIN`. The password is the one the owner specified for this setup. Do not share the included `.env` file. Before a public launch, replace the bootstrap credentials, set a strong random session secret, use HTTPS, and move admin identities/roles to Supabase Auth or another production identity provider. Never expose secrets through `VITE_*` variables.

## Homepage editor
The admin drawer now includes a Homepage editor for hero headline, subtitle, description, hero image URL/upload, floating-card text, category section copy/visibility, and editorial section copy/image/visibility. Settings are saved to the current browser's Local Storage. This is a local/demo content editor, not a multi-device CMS; connect it to a protected Supabase table and Storage bucket for production use. Uploaded images are limited to 1.2 MB to reduce Local Storage quota errors.
