-- Server-Cache für strukturierte Bundesliga-Transfers (Done Deals) aus
-- Sportmonks. Die Edge Function `transfers` iteriert die 18 Bundesliga-Teams,
-- normalisiert die Deals (Spieler, von→zu, Ablöse, Typ, Richtung) und legt sie
-- hier ab. Eine Abfrage versorgt alle Nutzer; der Sportmonks-Key bleibt
-- serverseitig.
--
-- Zugriff ausschließlich über service_role (Edge Function); RLS an, keine
-- Policy (Clients lesen nie direkt).
create table if not exists public.transfers_cache (
  key text primary key,
  fetched_at timestamptz not null default now(),
  payload jsonb not null
);

alter table public.transfers_cache enable row level security;
