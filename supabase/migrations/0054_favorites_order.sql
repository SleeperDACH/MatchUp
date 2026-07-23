-- Manuelle Sortier-Reihenfolge der Favoriten (Chips im Favoriten-Tab).
-- null = noch nie manuell sortiert → Anzeige nach Liga (Standard).
alter table public.user_favorites
  add column if not exists sort_order integer;
