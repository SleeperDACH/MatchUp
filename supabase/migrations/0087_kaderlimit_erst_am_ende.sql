-- Ein 1:1-Tausch scheiterte am Kader-Limit, obwohl er nichts ändert.
--
-- Gemeldet von zwei Teilnehmern: Stürmer gegen Stürmer getauscht, und die App
-- meldete „Kader-Limit erreicht". Am Ende des Tauschs hat jede Seite genau so
-- viele Stürmer wie vorher — der Fehler saß im **Zeitpunkt** der Prüfung.
--
-- `fantasy_respond_trade` bewegt die Spieler einzeln, als Schleife über
-- `fantasy_trade_items`, jeweils mit einem `update` von `manager_id`. Zwischen
-- zwei Schleifendurchläufen hat die empfangende Seite den neuen Spieler schon
-- und den eigenen noch — für einen Moment einen zu viel. Der Trigger aus 0083
-- lief `before insert or update` und sah genau diesen Moment.
--
-- Nachgestellt vor dem Fix (Limit = Bestand, dann 1:1 tauschen):
--   "Kader-Limit erreicht: höchstens 4 Stürmer in dieser Liga"
--
-- **Die Prüfung gehört ans Ende der Transaktion, nicht zwischen zwei Zeilen.**
-- Genau dafür gibt es `constraint trigger ... deferrable initially deferred`:
-- Er läuft beim Commit, wenn alle Bewegungen erledigt sind. Ein 1:1-Tausch
-- geht damit durch, ein echter Verstoß fällt weiterhin auf — nur eben mit
-- Blick auf den Endstand statt auf eine Momentaufnahme.
--
-- Zwei Eigenheiten von Constraint-Triggern, die man kennen muss:
--   * Sie müssen `after` sein. Der Rückgabewert wird ignoriert.
--   * Sie feuern auch für Zeilen, die in derselben Transaktion wieder
--     verschwunden sind. Deshalb steigt die Funktion aus, wenn es die Zeile
--     beim Commit gar nicht mehr gibt — sonst verböte sie einen Zugang, der
--     längst wieder weg ist.
--
-- Die Regel selbst ist unverändert: Wer schon über dem Limit liegt, behält
-- seine Spieler und kann auf dieser Position nichts mehr dazunehmen.

create or replace function public.fantasy_kaderlimit_pruefen()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_pos text; v_limit numeric; v_anzahl int; v_name text;
begin
  -- Beim Update nur prüfen, wenn der Spieler den Besitzer wechselt.
  if tg_op = 'UPDATE' and new.manager_id is not distinct from old.manager_id then
    return null;
  end if;

  -- Gibt es die Zeile am Ende der Transaktion noch, und gehört sie noch
  -- diesem Manager? Sonst ist nichts zu prüfen.
  if not exists (
    select 1 from fantasy_rosters
     where league_id = new.league_id
       and player_id = new.player_id
       and manager_id = new.manager_id
  ) then
    return null;
  end if;

  select position into v_pos from players where id = new.player_id;
  if v_pos is null then return null; end if;

  v_limit := public.fantasy_kaderlimit(new.league_id, v_pos);
  if v_limit is null then return null; end if;

  select count(*) into v_anzahl
    from fantasy_rosters r join players p on p.id = r.player_id
   where r.league_id = new.league_id
     and r.manager_id = new.manager_id
     and p.position = v_pos
     and r.player_id <> new.player_id;

  if v_anzahl >= v_limit then
    v_name := case v_pos
                when 'gk'  then 'Torhüter'
                when 'def' then 'Abwehrspieler'
                when 'mid' then 'Mittelfeldspieler'
                else            'Stürmer'
              end;
    raise exception
      'Kader-Limit erreicht: höchstens % % in dieser Liga', v_limit::int, v_name;
  end if;
  return null;
end$$;

drop trigger if exists fantasy_rosters_kaderlimit on public.fantasy_rosters;

create constraint trigger fantasy_rosters_kaderlimit
  after insert or update on public.fantasy_rosters
  deferrable initially deferred
  for each row execute function public.fantasy_kaderlimit_pruefen();
