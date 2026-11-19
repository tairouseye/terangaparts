-- =====================================================================
-- Teranga Parts — Notifications (client + administrateur)
--
-- Table reprise du module commun (separation d'avec TerangaMobility) :
-- seules les notifications sont conservees, sans le module vehicules.
-- =====================================================================

create table notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references profiles(id) on delete cascade, -- destinataire client
  target_role user_role,                                      -- ex: 'admin'
  title       text not null,
  body        text,
  type        text,        -- 'quote', 'payment', 'tracking'...
  related_id  uuid,
  is_read     boolean not null default false,
  created_at  timestamptz not null default now()
);
create index idx_notif_user on notifications(user_id);
create index idx_notif_role on notifications(target_role);

alter table notifications enable row level security;

-- Destinataire (client) ou admin pour le role admin.
create policy "notif: destinataire lecture"
  on notifications for select using (
    user_id = auth.uid() or (target_role = 'admin' and is_admin())
  );
create policy "notif: destinataire maj (lu)"
  on notifications for update using (
    user_id = auth.uid() or (target_role = 'admin' and is_admin())
  );
create policy "notif: admin insert"
  on notifications for insert with check (is_admin());
-- (les notifications sont surtout creees cote serveur / fonctions security definer)
