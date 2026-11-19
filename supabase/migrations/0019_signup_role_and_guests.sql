-- =====================================================================
-- Teranga Parts — Inscription sure + demandes sans compte (invites)
--
-- 1. FAILLE CORRIGEE : handle_new_user() lisait le role dans les metadata
--    envoyees par le navigateur a l'inscription. N'importe qui pouvait donc
--    creer un compte avec {"role": "admin"} et obtenir tous les droits.
--    Desormais, tout nouveau compte est 'client'. Les roles 'admin' et
--    'partner_kr' ne s'attribuent QUE par un admin (SQL ou policy admin),
--    et le trigger 0013 empeche un non-admin de modifier son propre role.
--
-- 2. Invites : l'app ouvre une session ANONYME Supabase (signInAnonymously)
--    au moment ou le visiteur envoie sa demande. Le profil est cree par ce
--    meme trigger avec le nom et le WhatsApp saisis. Le client peut ensuite
--    rattacher un email + mot de passe a ce meme compte : ses demandes le
--    suivent. Les policies existantes (client_id = auth.uid()) s'appliquent
--    telles quelles.
-- =====================================================================

create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, whatsapp, role)
  values (
    new.id,
    left(btrim(coalesce(new.raw_user_meta_data->>'full_name', '')), 120),
    left(btrim(coalesce(new.raw_user_meta_data->>'whatsapp', '')), 40),
    'client'
  );
  return new;
end;
$$;
