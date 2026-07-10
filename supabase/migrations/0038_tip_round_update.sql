-- Der Ersteller darf Wertung & Modi seiner Tipprunde nachträglich ändern
-- (Liga-Einstellungen im Liga-Tab). Bisher gab es nur select/insert/delete.

create policy "Ersteller ändert seine Tipprunde"
  on public.tip_rounds for update
  using (created_by = auth.uid())
  with check (created_by = auth.uid());
