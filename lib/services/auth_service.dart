import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/app_user.dart';
import '../models/enums.dart';

/// Adresse de retour des liens envoyes par email (confirmation, nouveau mot
/// de passe) : l'adresse du site en cours, sinon le domaine de production.
String siteRedirectUrl() =>
    Uri.base.hasScheme && Uri.base.scheme.startsWith('http')
        ? '${Uri.base.origin}/'
        : 'https://terangaparts.gesprosn.org/';

/// Acces centralise a Supabase Auth + profil.
class AuthService {
  final SupabaseClient _client;
  AuthService(this._client);

  SupabaseClient get client => _client;
  Session? get currentSession => _client.auth.currentSession;
  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get onAuthChange => _client.auth.onAuthStateChange;

  /// Inscription. Le profil est cree cote serveur par le trigger
  /// handle_new_user() a partir des metadata.
  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String whatsapp,
    UserRole role = UserRole.client,
  }) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      // Le lien de confirmation ramene TOUJOURS sur le site (et non sur le
      // « Site URL » par defaut de Supabase, souvent localhost).
      emailRedirectTo: siteRedirectUrl(),
      data: {
        'full_name': fullName,
        'whatsapp': whatsapp,
        // Indicatif seulement : le serveur attribue toujours le role client.
        'role': role.dbValue,
        'signed_up_with_password': true,
      },
    );
  }

  /// Session invitee (anonyme) : permet d'envoyer une demande SANS compte.
  /// Le profil (nom + WhatsApp) est cree cote serveur par handle_new_user().
  Future<void> signInAsGuest({
    required String fullName,
    required String whatsapp,
  }) async {
    await _client.auth.signInAnonymously(
      data: {'full_name': fullName, 'whatsapp': whatsapp},
    );
  }

  /// Garantit une session (invitee si besoin) avant un appel serveur qui
  /// l'exige (lecture de photo). Nom et WhatsApp seront ajoutes a l'envoi.
  Future<void> ensureSession() async {
    if (currentUser != null) return;
    await _client.auth.signInAnonymously();
  }

  /// Vrai si la session courante est une session invitee (sans email).
  bool get isGuest => currentUser?.isAnonymous ?? false;

  /// Met a jour nom + WhatsApp du profil de l'utilisateur connecte.
  Future<void> updateContact({
    required String fullName,
    required String whatsapp,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) return;
    await _client
        .from('profiles')
        .update({'full_name': fullName, 'whatsapp': whatsapp}).eq('id', uid);
  }

  /// Etape 1 de la creation de compte d'un invite : rattache un email au
  /// compte existant (les demandes suivent). Supabase envoie un lien de
  /// confirmation qui ramene sur [redirectTo].
  Future<void> attachEmail(String email, {String? redirectTo}) async {
    await _client.auth.updateUser(
      UserAttributes(email: email),
      emailRedirectTo: redirectTo,
    );
  }

  /// Etape 2 : choix du mot de passe (une fois l'email confirme).
  Future<void> setPassword(String password) async {
    await _client.auth.updateUser(
      UserAttributes(password: password, data: {'password_set': true}),
    );
  }

  /// Ancien invite dont l'email est confirme mais qui n'a pas encore choisi
  /// de mot de passe.
  bool get needsPassword {
    final u = currentUser;
    if (u == null || u.isAnonymous) return false;
    if (u.email == null || u.email!.isEmpty) return false;
    final meta = u.userMetadata ?? const {};
    return meta['password_set'] != true &&
        meta['signed_up_with_password'] != true;
  }

  Future<void> signIn({required String email, required String password}) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Envoie un email de reinitialisation du mot de passe.
  /// [redirectTo] : URL de retour dans l'app (ou le lien de recuperation ouvre
  /// l'ecran « nouveau mot de passe »).
  Future<void> sendPasswordReset(String email, {String? redirectTo}) {
    return _client.auth.resetPasswordForEmail(email, redirectTo: redirectTo);
  }

  /// Definit un nouveau mot de passe (session de recuperation active).
  Future<void> updatePassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  /// Recupere le profil (dont le role) de l'utilisateur connecte.
  Future<AppUser?> fetchProfile() async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    final data =
        await _client.from('profiles').select().eq('id', uid).maybeSingle();
    if (data == null) return null;
    return AppUser.fromJson(data);
  }
}
