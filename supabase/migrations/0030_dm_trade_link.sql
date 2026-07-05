-- Direktnachrichten können auf ein Trade-Angebot verweisen, damit man das
-- Angebot direkt aus dem Chat annehmen/ablehnen kann. Bleibt das Angebot
-- erhalten? -> die Nachricht verlinkt es per trade_id; wird der Trade gelöscht,
-- bleibt die Nachricht (Link auf null).

alter table public.direct_messages
  add column if not exists trade_id uuid
    references public.fantasy_trades (id) on delete set null;
