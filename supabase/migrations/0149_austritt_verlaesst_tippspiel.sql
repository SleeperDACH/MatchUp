-- Wer eine Fantasy-Liga verlässt, verlässt auch ihr gekoppeltes Tippspiel.
--
-- Gemeldet: Ein Nutzer bekam nach dem Austritt weiter Tipp-Erinnerungen.
-- 0064 hatte Austritte bewusst stehen lassen („Tipps bleiben"), aber die
-- Mitgliedschaft in `tip_round_members` ist mehr als die Tipps: Sie macht die
-- Runde sichtbar (RLS), lässt weiter tippen und ist die Empfängerliste für
-- Tipp-Erinnerungen und den Runden-Chat. Gezählt am 29.10.2026: zwei
-- verwaiste Manager in „BuLi 26/27", beide ohne einen einzigen Tipp.
--
-- Jetzt räumt derselbe Trigger, der beim Beitritt einträgt, beim Austritt
-- aus — Verlassen, Kick und Admin-Übergabe laufen alle über
-- `_fantasy_vacate` (vacant = true), das Übernehmen eines verwaisten Slots
-- löscht die Zeile. Die Tipps und Bonustipps bleiben stehen: Die Tabelle
-- rechnet über die Mitglieder, sie zählen also nicht mehr mit, und wer
-- zurückkommt, findet sie wieder.
--
-- War der Austretende Admin der Tipprunde, geht das Amt an den Admin der
-- Fantasy-Liga (bei `fantasy_transfer_and_leave` ist das schon der neue).

create or replace function public.fantasy_member_sync_tip()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_round uuid; v_runden_admin uuid; v_liga_admin uuid;
begin
  if tg_op = 'DELETE'
     or (tg_op = 'UPDATE' and (NEW.vacant or NEW.pending)) then
    select id, created_by into v_round, v_runden_admin
      from tip_rounds where fantasy_league_id = OLD.league_id;
    if v_round is null then
      return coalesce(NEW, OLD);
    end if;
    if v_runden_admin = OLD.user_id then
      select created_by into v_liga_admin
        from fantasy_leagues where id = OLD.league_id;
      if v_liga_admin is null or v_liga_admin = OLD.user_id then
        -- Kein anderer Admin in Sicht: lieber Mitglied bleiben als eine
        -- Runde ohne Admin hinterlassen.
        return coalesce(NEW, OLD);
      end if;
      insert into tip_round_members (round_id, user_id)
        values (v_round, v_liga_admin)
      on conflict do nothing;
      update tip_rounds set created_by = v_liga_admin where id = v_round;
    end if;
    delete from tip_round_members
      where round_id = v_round and user_id = OLD.user_id;
    return coalesce(NEW, OLD);
  end if;

  if NEW.vacant or NEW.pending then return NEW; end if;
  select id into v_round from tip_rounds where fantasy_league_id = NEW.league_id;
  if v_round is not null then
    insert into tip_round_members (round_id, user_id)
      values (v_round, NEW.user_id)
    on conflict do nothing;
  end if;
  return NEW;
end$$;

drop trigger if exists fantasy_member_sync_tip_trg on public.fantasy_league_members;
create trigger fantasy_member_sync_tip_trg
  after insert or update of vacant, pending or delete
  on public.fantasy_league_members
  for each row execute function public.fantasy_member_sync_tip();

-- Bestand: wer schon draußen ist, kommt jetzt auch aus dem Tippspiel.
delete from public.tip_round_members m
 using public.tip_rounds tr
 where tr.id = m.round_id
   and tr.fantasy_league_id is not null
   and m.user_id <> tr.created_by
   and not exists (select 1 from public.fantasy_league_members f
                    where f.league_id = tr.fantasy_league_id
                      and f.user_id = m.user_id
                      and not f.vacant and not f.pending);
