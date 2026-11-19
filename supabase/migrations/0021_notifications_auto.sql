-- =====================================================================
-- Teranga Parts — Notifications automatiques (v1.3.0)
--
-- Les notifications (cloche) etaient prevues mais rien ne les creait.
-- Des triggers les ecrivent desormais cote serveur, a chaque evenement :
--
--   parts_requests INSERT              -> admin  : nouvelle demande
--   parts_requests status devis_envoye -> client : votre devis est pret
--   orders INSERT (acompte paye)       -> admin  : acompte recu
--   orders status change               -> client : etape de la commande
--                                       -> admin  : solde paye (status payee)
--
-- Fonctions SECURITY DEFINER : un client n'a pas le droit d'ecrire dans
-- notifications (policy « admin insert »), le trigger le fait pour lui, avec
-- un contenu fixe (aucun texte libre du client hors nom de piece et nom).
-- =====================================================================

-- Libelle francais d'un statut (aligne sur OrderStatus.label cote app).
create or replace function order_status_label(s order_status)
returns text language sql immutable as $$
  select case s
    when 'nouvelle_demande'   then 'Nouvelle demande'
    when 'recherche_coree'    then 'Recherche en Corée'
    when 'piece_trouvee'      then 'Pièce trouvée'
    when 'devis_envoye'       then 'Devis envoyé'
    when 'acompte_paye'       then 'Acompte payé'
    when 'commande_confirmee' then 'Commande confirmée'
    when 'piece_achetee'      then 'Pièce achetée'
    when 'expediee'           then 'Expédiée'
    when 'en_transit'         then 'En transit'
    when 'arrivee_senegal'    then 'Arrivée au Sénégal'
    when 'solde_demande'      then 'Solde demandé'
    when 'payee'              then 'Payée'
    when 'livree'             then 'Livrée'
  end;
$$;

-- --- Demandes de pieces --------------------------------------------------
create or replace function notify_parts_request()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_client  text;
  v_vehicle text;
begin
  v_vehicle := nullif(btrim(concat_ws(' ', new.vehicle_brand, new.vehicle_model,
                                      new.vehicle_year::text)), '');

  if tg_op = 'INSERT' then
    select nullif(btrim(full_name), '') into v_client
      from profiles where id = new.client_id;
    insert into notifications (target_role, title, body, type, related_id)
    values ('admin', 'Nouvelle demande de pièce',
            left(new.part_name, 120)
              || coalesce(' — ' || v_vehicle, '')
              || coalesce(' — ' || v_client, ''),
            'parts_request', new.id);

  elsif tg_op = 'UPDATE' and new.status is distinct from old.status
        and new.status = 'devis_envoye' then
    insert into notifications (user_id, title, body, type, related_id)
    values (new.client_id, 'Votre devis est prêt',
            left(new.part_name, 120) || coalesce(' — ' || v_vehicle, '')
              || '. Consultez-le dans « Mes devis ».',
            'quote', new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_parts_request on parts_requests;
create trigger trg_notify_parts_request
  after insert or update of status on parts_requests
  for each row execute function notify_parts_request();

-- --- Commandes -----------------------------------------------------------
create or replace function notify_order()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_client text;
begin
  select nullif(btrim(full_name), '') into v_client
    from profiles where id = new.client_id;

  if tg_op = 'INSERT' then
    -- Commande creee par pay_deposit : l'acompte vient d'etre declare.
    insert into notifications (target_role, title, body, type, related_id)
    values ('admin', 'Acompte 70 % déclaré',
            'Commande de ' || coalesce(v_client, 'un client')
              || ' — vérifiez la réception du paiement avant de confirmer.',
            'payment', new.id);

  elsif tg_op = 'UPDATE' and new.status is distinct from old.status then
    insert into notifications (user_id, title, body, type, related_id)
    values (new.client_id, 'Suivi de votre commande',
            'Nouvelle étape : ' || order_status_label(new.status) || '.',
            'tracking', new.id);

    if new.status = 'payee' then
      insert into notifications (target_role, title, body, type, related_id)
      values ('admin', 'Solde 30 % déclaré',
              'Commande de ' || coalesce(v_client, 'un client')
                || ' — vérifiez la réception avant la livraison.',
              'payment', new.id);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_order on orders;
create trigger trg_notify_order
  after insert or update of status on orders
  for each row execute function notify_order();
