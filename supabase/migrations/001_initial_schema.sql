-- SSTREAND SHOP schema for Supabase PostgreSQL.
-- Apply with `supabase db push` after linking your own Supabase project.
create extension if not exists pgcrypto;

create type public.app_role as enum ('customer','admin');
create type public.order_status as enum ('pending','confirmed','processing','shipped','delivered','cancelled','refunded');
create type public.payment_status as enum ('pending','awaiting_verification','paid','failed','refunded');
create type public.payment_method as enum ('cod','bkash','nagad','bank_transfer');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '', phone text, email text,
  role public.app_role not null default 'customer',
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.categories (
  id uuid primary key default gen_random_uuid(), name text not null unique, slug text not null unique,
  description text not null default '', image_url text, sort_order int not null default 0,
  is_active boolean not null default true, created_at timestamptz not null default now()
);
create table public.products (
  id uuid primary key default gen_random_uuid(), category_id uuid references public.categories(id) on delete set null,
  name text not null, slug text not null unique, sku text not null unique,
  description text not null default '', specifications jsonb not null default '{}'::jsonb,
  regular_price numeric(12,2) not null check (regular_price >= 0), sale_price numeric(12,2) check (sale_price is null or sale_price >= 0),
  stock_quantity int not null default 0 check (stock_quantity >= 0),
  is_published boolean not null default false, is_featured boolean not null default false,
  authenticity_note text, rating numeric(2,1), review_count int not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  check (sale_price is null or sale_price <= regular_price)
);
create index products_category_idx on public.products(category_id);
create index products_published_created_idx on public.products(is_published, created_at desc);
create index products_name_search_idx on public.products using gin (to_tsvector('simple', name || ' ' || description || ' ' || sku));
create table public.product_media (
  id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id) on delete cascade,
  media_type text not null check (media_type in ('image','video')), url text not null, alt_text text not null default '', sort_order int not null default 0
);
create table public.product_variants (
  id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id) on delete cascade,
  name text not null, value text not null, sku text unique, price_delta numeric(12,2) not null default 0,
  stock_quantity int not null default 0 check (stock_quantity >= 0), unique(product_id,name,value)
);
create table public.addresses (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  recipient_name text not null, phone text not null, district text not null, upazila text not null default '', full_address text not null,
  is_default boolean not null default false, created_at timestamptz not null default now()
);
create table public.carts (
  id uuid primary key default gen_random_uuid(), user_id uuid unique references public.profiles(id) on delete cascade,
  guest_token_hash text unique, items jsonb not null default '[]'::jsonb, updated_at timestamptz not null default now(),
  check ((user_id is not null) <> (guest_token_hash is not null))
);
create table public.wishlists (
  user_id uuid not null references public.profiles(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade, created_at timestamptz not null default now(),
  primary key(user_id, product_id)
);
create table public.coupons (
  id uuid primary key default gen_random_uuid(), code text not null unique, discount_type text not null check(discount_type in ('percentage','fixed')),
  discount_value numeric(12,2) not null check(discount_value > 0), minimum_order numeric(12,2) not null default 0,
  max_uses int, uses_count int not null default 0, starts_at timestamptz, expires_at timestamptz,
  is_active boolean not null default true, check (max_uses is null or max_uses >= uses_count)
);
create table public.orders (
  id uuid primary key default gen_random_uuid(), order_number text not null unique default ('SS-' || upper(substr(encode(gen_random_bytes(8),'hex'),1,10))),
  user_id uuid references public.profiles(id) on delete set null,
  customer_name text not null, customer_phone text not null, customer_email text,
  district text not null, upazila text not null default '', delivery_address text not null, order_notes text not null default '',
  status public.order_status not null default 'pending', payment_method public.payment_method not null default 'cod',
  payment_status public.payment_status not null default 'pending', currency text not null default 'BDT' check(currency='BDT'),
  subtotal numeric(12,2) not null check(subtotal >= 0), discount_total numeric(12,2) not null default 0 check(discount_total >= 0),
  delivery_fee numeric(12,2) not null default 0 check(delivery_fee >= 0), total numeric(12,2) not null check(total >= 0),
  coupon_code text, tracking_number text, idempotency_key text unique,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index orders_user_created_idx on public.orders(user_id, created_at desc);
create index orders_phone_idx on public.orders(customer_phone);
create table public.order_items (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null, product_name text not null, sku text not null,
  variant_snapshot jsonb not null default '{}'::jsonb, unit_price numeric(12,2) not null check(unit_price >= 0),
  quantity int not null check(quantity > 0), line_total numeric(12,2) not null check(line_total >= 0)
);
create table public.payments (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete cascade,
  provider public.payment_method not null, provider_transaction_id text unique, provider_reference text,
  amount numeric(12,2) not null check(amount >= 0), status public.payment_status not null default 'pending',
  verified_at timestamptz, provider_payload jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);
create table public.reviews (
  id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade, order_id uuid references public.orders(id) on delete set null,
  rating int not null check(rating between 1 and 5), title text not null default '', body text not null default '',
  is_published boolean not null default false, created_at timestamptz not null default now(), unique(product_id,user_id,order_id)
);
create table public.store_settings (
  key text primary key, value jsonb not null default '{}'::jsonb, updated_at timestamptz not null default now(), updated_by uuid references public.profiles(id) on delete set null
);
create table public.homepage_content (
  key text primary key, content jsonb not null default '{}'::jsonb, published boolean not null default true,
  updated_at timestamptz not null default now(), updated_by uuid references public.profiles(id) on delete set null
);
create table public.admin_audit_log (
  id uuid primary key default gen_random_uuid(), actor_id uuid references public.profiles(id) on delete set null,
  action text not null, entity_type text not null, entity_id text, metadata jsonb not null default '{}'::jsonb, created_at timestamptz not null default now()
);

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id, full_name, email) values(new.id, coalesce(new.raw_user_meta_data->>'full_name',''), new.email) on conflict(id) do nothing;
  return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_media enable row level security;
alter table public.product_variants enable row level security;
alter table public.addresses enable row level security;
alter table public.carts enable row level security;
alter table public.wishlists enable row level security;
alter table public.coupons enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payments enable row level security;
alter table public.reviews enable row level security;
alter table public.store_settings enable row level security;
alter table public.homepage_content enable row level security;
alter table public.admin_audit_log enable row level security;

create policy "profiles read own or admin" on public.profiles for select to authenticated using (id=auth.uid() or public.is_admin());
create policy "profiles update own or admin" on public.profiles for update to authenticated using (id=auth.uid() or public.is_admin()) with check (id=auth.uid() or public.is_admin());
create policy "public read active categories" on public.categories for select to anon,authenticated using (is_active or public.is_admin());
create policy "admins manage categories" on public.categories for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "public read published products" on public.products for select to anon,authenticated using (is_published or public.is_admin());
create policy "admins manage products" on public.products for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "public read media for published products" on public.product_media for select to anon,authenticated using (exists(select 1 from public.products p where p.id=product_id and p.is_published) or public.is_admin());
create policy "admins manage product media" on public.product_media for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "public read variants for published products" on public.product_variants for select to anon,authenticated using (exists(select 1 from public.products p where p.id=product_id and p.is_published) or public.is_admin());
create policy "admins manage variants" on public.product_variants for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "customers manage own addresses" on public.addresses for all to authenticated using (user_id=auth.uid() or public.is_admin()) with check (user_id=auth.uid() or public.is_admin());
create policy "customers manage own cart" on public.carts for all to authenticated using (user_id=auth.uid() or public.is_admin()) with check (user_id=auth.uid() or public.is_admin());
create policy "customers manage own wishlist" on public.wishlists for all to authenticated using (user_id=auth.uid() or public.is_admin()) with check (user_id=auth.uid() or public.is_admin());
create policy "admins manage coupons" on public.coupons for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins read all orders customers own" on public.orders for select to authenticated using (user_id=auth.uid() or public.is_admin());
create policy "admins update orders" on public.orders for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins read order items customers own" on public.order_items for select to authenticated using (exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.is_admin())));
create policy "admins manage order items" on public.order_items for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "customers read own payments admin all" on public.payments for select to authenticated using (exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.is_admin())));
create policy "admins manage payments" on public.payments for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "public read published reviews" on public.reviews for select to anon,authenticated using (is_published or user_id=auth.uid() or public.is_admin());
create policy "customers create own reviews" on public.reviews for insert to authenticated with check (user_id=auth.uid());
create policy "customers update own unpublished reviews admin" on public.reviews for update to authenticated using ((user_id=auth.uid() and not is_published) or public.is_admin()) with check ((user_id=auth.uid() and not is_published) or public.is_admin());
create policy "admins manage settings" on public.store_settings for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "public read published homepage" on public.homepage_content for select to anon,authenticated using (published or public.is_admin());
create policy "admins manage homepage" on public.homepage_content for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admins read audit logs" on public.admin_audit_log for select to authenticated using (public.is_admin());
create policy "admins insert audit logs" on public.admin_audit_log for insert to authenticated with check (public.is_admin());

-- Public storefront read roles only; writes to inventory/orders/payment must go through trusted server functions.
grant select on public.categories, public.products, public.product_media, public.product_variants, public.reviews, public.homepage_content to anon, authenticated;
grant select, insert, update, delete on public.addresses, public.carts, public.wishlists to authenticated;
revoke update on public.profiles from authenticated;
grant update(full_name, phone, email, updated_at) on public.profiles to authenticated;
grant select on public.orders, public.order_items, public.payments to authenticated;
grant update on public.orders to authenticated;
grant select, insert, update, delete on public.categories, public.products, public.product_media, public.product_variants, public.coupons, public.orders, public.order_items, public.payments, public.store_settings, public.homepage_content, public.admin_audit_log to authenticated;

insert into public.categories(name,slug,sort_order) values
 ('Women’s Fashion','womens-fashion',1),('Women’s Handbags','womens-handbags',2),('Skincare','skincare',3),('Beauty & Cosmetics','beauty-cosmetics',4),('New Arrivals','new-arrivals',5),('Best Sellers','best-sellers',6),('Sale & Offers','sale-offers',7)
on conflict(slug) do nothing;
insert into public.homepage_content(key,content) values
 ('hero','{"headline":"China Import Beauty & Radiant Skincare 2026","subtitle":"100% authentic and comfortable fashion.","primaryButton":"SHOP NOW","secondaryButton":"EXPLORE COLLECTIONS","desktopImage":"","mobileImage":""}'::jsonb),
 ('announcement','{"text":"Complimentary delivery on orders over ৳3,500"}'::jsonb)
on conflict(key) do nothing;
