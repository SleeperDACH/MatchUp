-- Ligaspezifischer Anzeigename (Teamname) je Mitglied — für Fantasy und
-- Tippspiel. Leer/NULL = kein Teamname (dann gilt der globale Nutzername).
-- Gesetzt per SECURITY-DEFINER-RPC, damit jeder nur den eigenen Namen ändert.

alter table public.fantasy_league_members
  add column if not exists team_name text;

alter table public.tip_round_members
  add column if not exists team_name text;

create or replace function public.fantasy_set_team_name(
  p_league_id uuid, p_name text)
returns void
language sql security definer set search_path = public as $$
  update public.fantasy_league_members
     set team_name = nullif(btrim(p_name), '')
   where league_id = p_league_id and user_id = auth.uid();
$$;

create or replace function public.tip_set_team_name(
  p_round_id uuid, p_name text)
returns void
language sql security definer set search_path = public as $$
  update public.tip_round_members
     set team_name = nullif(btrim(p_name), '')
   where round_id = p_round_id and user_id = auth.uid();
$$;
