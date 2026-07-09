-- Bonustipps: mehrere Teams je Frage erlauben (z. B. „Absteiger" = 2 Teams).
-- Primärschlüssel um team_id erweitern, damit pro (Runde, Mitglied, Frage)
-- mehrere Team-Antworten existieren können.

alter table public.tip_bonus_answers
  drop constraint tip_bonus_answers_pkey;

alter table public.tip_bonus_answers
  add constraint tip_bonus_answers_pkey
  primary key (round_id, user_id, question, team_id);
