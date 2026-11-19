-- =====================================================================
-- Teranga Parts — Journal des analyses de photos (lecture VIN / piece)
--
-- La fonction serveur `analyze-photo` lit une photo (carte grise ou piece)
-- avec l'IA. Chaque appel est journalise ici pour LIMITER le nombre
-- d'analyses par utilisateur et par jour (anti-abus, maitrise du cout).
--
-- Aucune policy : seule la fonction serveur (cle service_role) lit et ecrit.
-- Les clients n'y ont aucun acces (RLS active, rien d'autorise).
-- =====================================================================

create table photo_analyses (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  kind       text not null check (kind in ('vin', 'part')),
  ok         boolean not null default false,
  created_at timestamptz not null default now()
);
create index idx_photo_analyses_user_time on photo_analyses(user_id, created_at desc);

alter table photo_analyses enable row level security;
