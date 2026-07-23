-- Cache für den Sportmonks-Proxy (Edge Function `sportmonks`).
--
-- Der Client ruft nie direkt Sportmonks (Key bleibt serverseitig), sondern die
-- Function; deren Antworten werden hier je `cache_key` mit Zeitstempel abgelegt.
-- Eine Abfrage versorgt alle Nutzer und schont das Sportmonks-Limit. TTL wird
-- in der Function bestimmt (kurz für Live-Fixtures, länger für Tabellen).

create table if not exists public.sportmonks_cache (
  cache_key text primary key,
  fetched_at timestamptz not null default now(),
  payload jsonb not null
);

-- Nur der Service-Role-Key (Edge Function) schreibt/liest; Clients kommen nur
-- über die Function an die Daten. RLS an, keine Policies → für normale Nutzer
-- gesperrt.
alter table public.sportmonks_cache enable row level security;
