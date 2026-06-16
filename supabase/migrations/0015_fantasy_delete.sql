-- Der Ersteller darf seine Fantasy-Liga löschen. Die abhängigen Tabellen
-- (Mitglieder, Kader, Lineups, Waiver, Draft) hängen per ON DELETE CASCADE
-- an fantasy_leagues und werden automatisch mit entfernt.
create policy "Ersteller löscht seine Fantasy-Liga"
  on public.fantasy_leagues for delete
  using (created_by = auth.uid());
