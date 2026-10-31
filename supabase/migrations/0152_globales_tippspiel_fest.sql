-- Das Globale Tippspiel ist fest (29.10.2026, auf Ansage: „Wertung ist im
-- Globalen Tippspiel fix"). Die App bietet die Einstellungen nicht mehr an;
-- dieser Trigger hält es auch für direkte Aufrufe fest.
--
-- Fest sind: Wertung (4/3/2), Wettbewerb (nur 1. Bundesliga), Saison,
-- Sichtbarkeit und Beitrittsmodus (offen für alle). Name und Logo darf der
-- Admin weiter ändern.
--
-- Nebenbei geschlossen: `ist_global` war über die Update-Policy des
-- Erstellers frei setzbar — jeder hätte seine eigene Runde zum Globalen
-- Tippspiel erklären können (oder das echte zur gewöhnlichen Runde). Setzen
-- darf das Merkmal nur, wer ohne Nutzer-Kontext läuft (Migrationen,
-- Dienstkonto): `auth.uid()` ist dort null.

create or replace function public.tip_rounds_global_fest()
returns trigger language plpgsql set search_path = public as $$
begin
  if auth.uid() is null then return new; end if;
  if tg_op = 'INSERT' then
    if new.ist_global then
      raise exception 'Das Globale Tippspiel legt nur der Betreiber an.';
    end if;
    return new;
  end if;
  if new.ist_global is distinct from old.ist_global then
    raise exception 'Das Globale Tippspiel lässt sich nicht umstellen.';
  end if;
  if old.ist_global and (
       new.scoring    is distinct from old.scoring or
       new.league_id  is distinct from old.league_id or
       new.league_ids is distinct from old.league_ids or
       new.season     is distinct from old.season or
       new.visibility is distinct from old.visibility or
       new.join_policy is distinct from old.join_policy) then
    raise exception 'Wertung, Wettbewerb und Sichtbarkeit des Globalen Tippspiels sind fest.';
  end if;
  return new;
end$$;

drop trigger if exists tip_rounds_global_fest_trg on public.tip_rounds;
create trigger tip_rounds_global_fest_trg
  before insert or update on public.tip_rounds
  for each row execute function public.tip_rounds_global_fest();
