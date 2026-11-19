-- =====================================================================
-- Teranga Parts — Durcissement securite (audit)
--
-- La RLS est ROW-level, pas COLUMN-level : une policy UPDATE "ligne m'appartient"
-- laisse le client modifier N'IMPORTE QUELLE colonne de SA ligne. Une faille
-- d'elevation de privilege en decoulait :
--   profiles : un client pouvait se donner le role 'admin'.
-- On la neutralise par un trigger BEFORE UPDATE qui, pour un utilisateur
-- CONNECTE non-admin, remet la colonne protegee a son ancienne valeur.
-- Les contextes serveur (auth.uid() null : cron, service_role, SQL admin) et
-- les RPC legitimes (drapeau de bypass) ne sont pas brides.
-- =====================================================================

-- 1. profiles : interdit le changement de role par un non-admin connecte.
create or replace function prevent_profile_privilege_escalation()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not is_admin() then
    new.role := old.role;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_profiles_no_escalation on profiles;
create trigger trg_profiles_no_escalation before update on profiles
  for each row execute function prevent_profile_privilege_escalation();
