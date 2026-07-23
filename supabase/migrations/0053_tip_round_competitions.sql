-- Mehrere Wettbewerbe je Tipprunde.
--
-- Bisher hatte eine Tipprunde genau eine Liga (`league_id`). Jetzt kann sie
-- mehrere Wettbewerbe kombinieren (1./2. Bundesliga + DFB-Pokal). Tipps, RLS-
-- Deadline und die Wertungs-View sind bereits **fixture-basiert und
-- liga-agnostisch** — es genügt, die Wettbewerbsliste zu speichern (steuert,
-- welche Spiele zum Tippen angeboten werden). `league_id` bleibt als
-- Primär-/Kompatibilitätswert erhalten (= erster Wettbewerb).

alter table public.tip_rounds
  add column if not exists league_ids text[] not null default '{}';

-- Bestehende Runden: bisherige Einzel-Liga als Liste übernehmen.
update public.tip_rounds
  set league_ids = array[league_id]
  where league_ids = '{}';
