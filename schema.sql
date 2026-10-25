-- =====================================================
-- KODIGO URBAN · Esquema de Supabase (versión 10)
-- Pégalo completo en: Supabase > SQL Editor > New query > Run
-- Se puede ejecutar varias veces y también sobre una versión anterior.
-- =====================================================

create extension if not exists pgcrypto;

-- ---------- Productos ----------
create table if not exists public.products (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(btrim(name)) between 1 and 120),
  category    text not null,
  subcategory text not null default '',
  price       numeric(10,2) not null check (price >= 0),
  description text not null default '',
  images      text[] not null default '{}',
  sizes       text[] not null default '{}',
  active      boolean not null default true,
  featured    boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
-- Versiones anteriores limitaban las categorías a una lista fija: se quita ese límite.
alter table public.products drop constraint if exists products_category_check;
alter table public.products add column if not exists subcategory text not null default '';
-- Enlaces de pago propios de cada producto (opcionales)
alter table public.products add column if not exists paypal_url text not null default '';
alter table public.products add column if not exists wompi_url  text not null default '';
create index if not exists products_category_idx on public.products (category);
create index if not exists products_created_idx  on public.products (created_at desc);

-- ---------- Categorías y subcategorías ----------
create table if not exists public.categories (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(btrim(name)) between 1 and 40),
  slug       text not null check (slug ~ '^[a-z0-9-]+$'),
  parent_id  uuid references public.categories(id) on delete cascade,
  sort       int not null default 0,
  created_at timestamptz not null default now()
);
create unique index if not exists categories_top_slug on public.categories (slug) where parent_id is null;
create unique index if not exists categories_sub_slug on public.categories (parent_id, slug) where parent_id is not null;

-- ---------- Ajustes del sitio (banners, colores, WhatsApp, pagos) ----------
create table if not exists public.settings (
  key        text primary key,
  value      jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- ---------- Pedidos ----------
create table if not exists public.orders (
  id              uuid primary key default gen_random_uuid(),
  code            text not null unique,
  customer_name   text not null,
  phone           text not null,
  department      text not null default '',
  address         text not null,
  notes           text not null default '',
  items           jsonb not null default '[]'::jsonb,
  total           numeric(12,2) not null check (total >= 0),
  method          text not null check (method in ('paypal','wompi','whatsapp')),
  status          text not null default 'pendiente' check (status in ('pendiente','pagado','enviado','cancelado')),
  whatsapp_number text not null default '',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists orders_created_idx on public.orders (created_at desc);

-- ---------- updated_at automático ----------
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists products_updated on public.products;
create trigger products_updated before update on public.products
  for each row execute function public.set_updated_at();
drop trigger if exists settings_updated on public.settings;
create trigger settings_updated before update on public.settings
  for each row execute function public.set_updated_at();
drop trigger if exists orders_updated on public.orders;
create trigger orders_updated before update on public.orders
  for each row execute function public.set_updated_at();

-- ---------- Crear pedido: el TOTAL lo calcula el servidor con los precios reales ----------
create or replace function public.create_order(
  p_items jsonb, p_name text, p_phone text, p_address text,
  p_department text, p_notes text, p_method text, p_wa text
) returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
  it      jsonb;
  pr      record;
  q       int;
  v_size  text;
  v_total numeric(12,2) := 0;
  v_lines jsonb := '[]'::jsonb;
  v_code  text;
  v_try   int := 0;
begin
  if p_items is null or jsonb_typeof(p_items) <> 'array'
     or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 40 then
    raise exception 'Carrito vacío o inválido';
  end if;
  if char_length(btrim(coalesce(p_name,''))) < 3
     or char_length(regexp_replace(coalesce(p_phone,''), '\D', '', 'g')) < 8
     or char_length(btrim(coalesce(p_address,''))) < 10 then
    raise exception 'Faltan datos de entrega';
  end if;
  if p_method is null or p_method not in ('paypal','wompi','whatsapp') then
    raise exception 'Método de pago inválido';
  end if;

  for it in select value from jsonb_array_elements(p_items) loop
    q := least(99, greatest(1, coalesce(nullif(it->>'qty','')::int, 1)));
    v_size := nullif(btrim(coalesce(it->>'size','')), '');
    select p.id, p.name, p.price, p.sizes into pr
      from public.products p
     where p.id = (it->>'id')::uuid and p.active = true;
    if not found then
      raise exception 'Un producto ya no está disponible';
    end if;
    if coalesce(array_length(pr.sizes,1),0) > 0 and (v_size is null or not (v_size = any(pr.sizes))) then
      raise exception 'Talla no válida para %', pr.name;
    end if;
    v_total := v_total + pr.price * q;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'id', pr.id, 'name', pr.name, 'size', v_size, 'qty', q, 'price', pr.price));
  end loop;

  loop
    v_code := 'KU-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    begin
      insert into public.orders (code, customer_name, phone, department, address, notes, items, total, method, whatsapp_number)
      values (v_code, left(btrim(p_name),80), left(btrim(p_phone),20), left(coalesce(p_department,''),40),
              left(btrim(p_address),300), left(coalesce(p_notes,''),200), v_lines, v_total, p_method, left(coalesce(p_wa,''),20));
      exit;
    exception when unique_violation then
      v_try := v_try + 1;
      if v_try > 5 then raise; end if;
    end;
  end loop;

  return jsonb_build_object('code', v_code, 'total', v_total, 'items', v_lines);
end $$;

revoke all on function public.create_order(jsonb,text,text,text,text,text,text,text) from public;
grant execute on function public.create_order(jsonb,text,text,text,text,text,text,text) to anon, authenticated;

-- ---------- Seguridad (RLS) ----------
-- Público: solo LEE productos activos, categorías y ajustes. Los pedidos solo se crean con create_order().
-- Administrador (usuario autenticado de Supabase Auth): lee y escribe todo.
alter table public.products   enable row level security;
alter table public.categories enable row level security;
alter table public.settings   enable row level security;
alter table public.orders     enable row level security;

drop policy if exists products_public_read on public.products;
create policy products_public_read on public.products
  for select using (active = true or auth.role() = 'authenticated');
drop policy if exists products_admin_write on public.products;
create policy products_admin_write on public.products
  for all to authenticated using (true) with check (true);

drop policy if exists categories_public_read on public.categories;
create policy categories_public_read on public.categories for select using (true);
drop policy if exists categories_admin_write on public.categories;
create policy categories_admin_write on public.categories
  for all to authenticated using (true) with check (true);

drop policy if exists settings_public_read on public.settings;
create policy settings_public_read on public.settings for select using (true);
drop policy if exists settings_admin_write on public.settings;
create policy settings_admin_write on public.settings
  for all to authenticated using (true) with check (true);

drop policy if exists orders_admin_all on public.orders;
create policy orders_admin_all on public.orders
  for all to authenticated using (true) with check (true);

-- ---------- Permisos de la API ----------
grant usage on schema public to anon, authenticated;
grant select on public.products, public.categories, public.settings to anon, authenticated;
grant insert, update, delete on public.products, public.categories, public.settings to authenticated;
grant select, update, delete on public.orders to authenticated;

-- ---------- Categorías iniciales ----------
insert into public.categories (name, slug, sort)
select v.n, v.s, v.o
from (values ('Gorras','gorras',1), ('Tenis','tenis',2), ('Sudaderas','sudaderas',3), ('Bóxer','boxer',4)) as v(n, s, o)
where not exists (select 1 from public.categories c where c.slug = v.s and c.parent_id is null);

-- ---------- Ajustes iniciales (solo si no existen) ----------
insert into public.settings (key, value) values (
  'site',
  '{
    "logo": "",
    "announce": "Haz tu pedido directo por WhatsApp",
    "intro": true,
    "theme": {"bg": "#f5f8fd", "accent": "#1d4ed8", "ink": "#0a1428"},
    "banners": [
      {"id": "b1", "active": true, "title": "Drop de temporada", "subtitle": "Promociones del mes en nuestra tienda",
       "cta": "Ver tienda", "link": "#/tienda", "image": "", "imageMobile": ""}
    ],
    "whatsapp": {"featured": 0, "numbers": [
      {"label": "", "number": "50360342681"},
      {"label": "", "number": "50373111251"},
      {"label": "", "number": "50375048017"}
    ]},
    "pay": {"paypal": true, "paypalId": "SPDJMSBSXJ2XQ", "wompi": true,
            "wompiUrl": "https://s.wompi.sv/2386409st8", "whatsapp": true},
    "notify": {"enabled": true, "email": "kodigourban126@gmail.com"}
  }'::jsonb
) on conflict (key) do nothing;

-- ---------- Productos iniciales (solo si la tabla está vacía) ----------
-- Las fotos viven en la carpeta img/ del sitio (van en el ZIP). Edítalas o bórralas desde el panel.
insert into public.products (name, category, price, description, images, featured, created_at)
select * from (values
  ('GORRA NEW ERA 59FIFTY · Yankees blanca', 'gorras', 30, 'Calidad top Quality', array['img/gorra-1.jpg']::text[], true, now() - interval '1 minutes'),
  ('GORRA NEW ERA 59FIFTY · Braves negra', 'gorras', 30, 'Calidad top Quality', array['img/gorra-2.jpg']::text[], true, now() - interval '2 minutes'),
  ('GORRA NEW ERA 59FIFTY · Dodgers blanca y negra', 'gorras', 30, 'Calidad top Quality', array['img/gorra-3.jpg']::text[], true, now() - interval '3 minutes'),
  ('GORRA NEW ERA 59FIFTY · Yankees blanca y negra', 'gorras', 30, 'Calidad top Quality', array['img/gorra-4.jpg']::text[], true, now() - interval '4 minutes'),
  ('GORRA NEW ERA 59FIFTY · Rockets Just Don negra', 'gorras', 30, 'Calidad top Quality', array['img/gorra-5.jpg']::text[], false, now() - interval '5 minutes'),
  ('GORRA NEW ERA 59FIFTY · Dodgers roja', 'gorras', 30, 'Calidad top Quality', array['img/gorra-6.jpg']::text[], false, now() - interval '6 minutes'),
  ('GORRA NEW ERA 59FIFTY · Bulls Just Don negra', 'gorras', 30, 'Calidad top Quality', array['img/gorra-7.jpg']::text[], false, now() - interval '7 minutes'),
  ('GORRA NEW ERA 59FIFTY · Pirates negra', 'gorras', 30, 'Calidad top Quality', array['img/gorra-8.jpg']::text[], false, now() - interval '8 minutes'),
  ('GORRA NEW ERA 59FIFTY · Raiders blanca', 'gorras', 30, 'Calidad top Quality', array['img/gorra-9.jpg']::text[], false, now() - interval '9 minutes'),
  ('GORRA NEW ERA 59FIFTY · Yankees roja', 'gorras', 30, 'Calidad top Quality', array['img/gorra-10.jpg']::text[], false, now() - interval '10 minutes')
) as v(name, category, price, description, images, featured, created_at)
where not exists (select 1 from public.products);

-- ---------- Almacenamiento de fotos (bucket público "media") ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media', 'media', true, 10485760,
        array['image/jpeg','image/png','image/webp','image/gif'])
on conflict (id) do update
  set public = true,
      file_size_limit = 10485760,
      allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif'];

do $$
begin
  drop policy if exists media_public_read on storage.objects;
  create policy media_public_read on storage.objects
    for select using (bucket_id = 'media');

  drop policy if exists media_admin_insert on storage.objects;
  create policy media_admin_insert on storage.objects
    for insert to authenticated with check (bucket_id = 'media');

  drop policy if exists media_admin_update on storage.objects;
  create policy media_admin_update on storage.objects
    for update to authenticated using (bucket_id = 'media') with check (bucket_id = 'media');

  drop policy if exists media_admin_delete on storage.objects;
  create policy media_admin_delete on storage.objects
    for delete to authenticated using (bucket_id = 'media');
exception when others then
  raise notice 'Aviso: no se pudieron crear las politicas de storage (%). Crealas en Storage > Policies del bucket media.', sqlerrm;
end $$;
