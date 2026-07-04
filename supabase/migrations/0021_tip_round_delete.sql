-- Der Ersteller einer Tipprunde darf sie löschen. Mitglieder, Tipps und
-- Chat-Nachrichten hängen per `on delete cascade` daran und gehen mit.

create policy "Ersteller kann Tipprunde löschen"
  on public.tip_rounds for delete
  using (created_by = auth.uid());
