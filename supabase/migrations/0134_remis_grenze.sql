-- Unentschieden bei knappem Ausgang (auf Ansage, 16.10.2026).
--
-- Ein Duell gilt als Unentschieden, wenn die beiden Wochensummen höchstens
-- `remis_grenze` Punkte auseinanderliegen. `null` heißt: aus — dann ist nur
-- exakte Punktgleichheit ein Unentschieden (die Regel bis heute).
--
-- * **Bestehende Ligen bleiben aus.** Die Spalte kommt ohne Wert dazu; der
--   Admin schaltet sie in den Einstellungen ein. Weil die Bilanz bei jedem
--   Aufruf neu gerechnet wird, gilt sie dann für alle Spieltage der Saison —
--   so gewollt.
-- * **Neue Ligen starten mit 5,0** — die App schickt den Wert beim Anlegen
--   mit. (Der Spaltenstandard hier ist in 0135 wieder entfernt, siehe dort.)
-- * Erlaubt sind 1 bis 20 Punkte, in ganzen Schritten wählbar.
--
-- Gerechnet wird ausschließlich in der App (`h2hStandings` mit
-- `remisGrenze`); keine SQL-Funktion wertet H2H-Duelle.

alter table public.fantasy_leagues
  add column if not exists remis_grenze numeric(4, 1);

alter table public.fantasy_leagues
  alter column remis_grenze set default 5.0;

alter table public.fantasy_leagues
  add constraint fantasy_leagues_remis_grenze_bereich
  check (remis_grenze is null or (remis_grenze >= 1 and remis_grenze <= 20));

-- **Jede Änderung steht im Liga-Chat.** Sie ändert rückwirkend Bilanzen und
-- Tabelle — wer gestern Zweiter war, kann heute Dritter sein. Das darf nicht
-- still passieren.
create or replace function public.fantasy_remis_grenze_melden()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_text text;
begin
  if new.remis_grenze is not distinct from old.remis_grenze then
    return new;
  end if;
  if new.remis_grenze is null then
    v_text := '⚖️ Regeländerung: Unentschieden gibt es nur noch bei '
      || 'Punktgleichheit. Gilt für alle Spieltage dieser Saison.';
  else
    v_text := '⚖️ Regeländerung: Ein Duell endet unentschieden, wenn höchstens '
      || replace(to_char(new.remis_grenze, 'FM990.0'), '.', ',')
      || ' Punkte dazwischen liegen. Gilt für alle Spieltage dieser Saison.';
  end if;
  perform public.fantasy_post_system_message(new.id, v_text);
  return new;
end;
$$;

revoke all on function public.fantasy_remis_grenze_melden() from public, anon, authenticated;

drop trigger if exists fantasy_remis_grenze_melden on public.fantasy_leagues;
create trigger fantasy_remis_grenze_melden
  after update of remis_grenze on public.fantasy_leagues
  for each row execute function public.fantasy_remis_grenze_melden();
