// Supabase Edge Function: server-authoritative order creation.
// Deploy with: supabase functions deploy create-order
// This validates current prices and stock in the database. Configure Supabase secrets before deployment.
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  const url = Deno.env.get('SUPABASE_URL'); const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return json({ error: 'Server is not configured.' }, 500);
  const authHeader = req.headers.get('Authorization') || '';
  const client = createClient(url, serviceKey, { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } });
  const userClient = createClient(url, Deno.env.get('SUPABASE_ANON_KEY') || '', { global: { headers: { Authorization: authHeader } }, auth: { persistSession: false } });
  const { data: { user } } = await userClient.auth.getUser();
  let body: any;
  try { body = await req.json(); } catch { return json({ error: 'Invalid JSON.' }, 400); }
  const { customer_name, customer_phone, customer_email = null, district, upazila = '', delivery_address, order_notes = '', payment_method = 'cod', items, idempotency_key } = body ?? {};
  if (!customer_name || !/^01[3-9]\d{8}$/.test(String(customer_phone || '')) || !district || !delivery_address || !Array.isArray(items) || items.length < 1 || items.length > 30) return json({ error: 'Please provide valid customer, delivery, and item details.' }, 400);
  if (!['cod','bkash','nagad','bank_transfer'].includes(payment_method)) return json({ error: 'Unsupported payment method.' }, 400);
  if (idempotency_key && (typeof idempotency_key !== 'string' || idempotency_key.length > 100)) return json({ error: 'Invalid idempotency key.' }, 400);
  if (idempotency_key) {
    const { data: prior } = await client.from('orders').select('id,order_number,status,payment_status,total').eq('idempotency_key', idempotency_key).maybeSingle();
    if (prior) return json({ order: prior, reused: true });
  }
  const quantities = new Map<string, number>();
  for (const item of items) {
    if (!item || typeof item.product_id !== 'string' || !Number.isInteger(item.quantity) || item.quantity < 1 || item.quantity > 20) return json({ error: 'Invalid product or quantity.' }, 400);
    quantities.set(item.product_id, (quantities.get(item.product_id) || 0) + item.quantity);
  }
  const ids = [...quantities.keys()];
  const { data: products, error: productError } = await client.from('products').select('id,name,sku,regular_price,sale_price,stock_quantity,is_published').in('id', ids);
  if (productError || !products || products.length !== ids.length) return json({ error: 'One or more products could not be found.' }, 400);
  let subtotal = 0;
  const orderItems = [];
  for (const p of products) {
    const quantity = quantities.get(p.id)!;
    if (!p.is_published) return json({ error: `${p.name} is unavailable.` }, 409);
    if (p.stock_quantity < quantity) return json({ error: `Not enough stock for ${p.name}.` }, 409);
    const price = Number(p.sale_price ?? p.regular_price); const line = Math.round(price * quantity * 100) / 100; subtotal += line;
    orderItems.push({ product_id: p.id, product_name: p.name, sku: p.sku, unit_price: price, quantity, line_total: line });
  }
  subtotal = Math.round(subtotal * 100) / 100;
  // Delivery is an example policy. Replace with server-side store_settings zone rules before launch.
  const delivery_fee = subtotal >= 3500 ? 0 : 80; const total = subtotal + delivery_fee;
  const payment_status = payment_method === 'cod' ? 'pending' : 'awaiting_verification';
  const { data: order, error: orderError } = await client.from('orders').insert({ user_id: user?.id ?? null, customer_name, customer_phone, customer_email, district, upazila, delivery_address, order_notes, payment_method, payment_status, subtotal, delivery_fee, discount_total: 0, total, idempotency_key: idempotency_key || null }).select('id,order_number,status,payment_status,total').single();
  if (orderError || !order) return json({ error: 'Could not create order. Please try again.' }, 500);
  const { error: itemsError } = await client.from('order_items').insert(orderItems.map(x => ({ ...x, order_id: order.id })));
  if (itemsError) { await client.from('orders').delete().eq('id', order.id); return json({ error: 'Could not save order items.' }, 500); }
  const { error: paymentError } = await client.from('payments').insert({ order_id: order.id, provider: payment_method, amount: total, status: payment_status });
  if (paymentError) return json({ error: 'Order created but payment record failed. Contact support with order ' + order.order_number }, 500);
  // Important: production must reserve/decrement inventory atomically using a Postgres RPC transaction with row locks.
  // This handler deliberately refuses to claim race-safe stock reservation until that RPC is installed.
  return json({ order, message: 'Order created. Inventory reservation must be enabled using the transaction RPC before production launch.' }, 201);
});
