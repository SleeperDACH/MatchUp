-- Server-Cache für den Bundesliga-News-Ticker (Transfers bzw. Verletzungen/
-- Sperren). Die Edge Function `news` holt einen öffentlichen RSS-Feed
-- (Google News), legt die geparsten Schlagzeilen hier ab und liefert sie an
-- die Clients. So versorgt eine Abfrage alle Nutzer und der Feed wird nicht
-- bei jedem App-Aufruf neu geladen.
--
-- Zugriff ausschließlich über service_role (Edge Function); Clients lesen
-- nie direkt, daher RLS an und bewusst keine Policy.
create table if not exists public.news_cache (
  topic text primary key,
  fetched_at timestamptz not null default now(),
  payload jsonb not null
);

alter table public.news_cache enable row level security;
-- Keine Policies: nur service_role (Edge Function) darf lesen/schreiben.
