-- Server-Cache für Wettquoten (the-odds-api.com). Die Edge Function `odds`
-- ruft die Quoten-API mit dem geheimen ODDS_API_KEY auf, legt die Antwort
-- hier ab und liefert sie an die Clients. So bleibt der Key serverseitig
-- und eine einzige Abfrage versorgt alle Nutzer (schont das Gratis-Limit
-- von ~500 Requests/Monat).
--
-- Zugriff ausschließlich über service_role (Edge Function); Clients lesen
-- nie direkt, daher RLS an und bewusst keine Policy.
create table if not exists public.odds_cache (
  sport text primary key,
  fetched_at timestamptz not null default now(),
  payload jsonb not null
);

alter table public.odds_cache enable row level security;
-- Keine Policies: nur service_role (Edge Function) darf lesen/schreiben.
