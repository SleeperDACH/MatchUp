-- Antworten im ligainternen Chat (Tippspiel wie Fantasy): jede Nachricht kann
-- optional auf eine andere Nachricht derselben Liga verweisen. Wird die
-- Original-Nachricht gelöscht, bleibt die Antwort erhalten (reply_to -> null).

alter table public.tip_round_messages
  add column if not exists reply_to uuid
    references public.tip_round_messages (id) on delete set null;

alter table public.fantasy_league_messages
  add column if not exists reply_to uuid
    references public.fantasy_league_messages (id) on delete set null;
