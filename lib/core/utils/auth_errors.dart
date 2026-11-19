import 'package:supabase_flutter/supabase_flutter.dart';

/// Traduit une erreur de connexion / d'envoi d'email en phrase claire
/// (inspire du fichier erreurs.js de GesSchool). Jamais de message technique
/// anglais a l'ecran.
String friendlyAuthError(Object error) {
  if (error is AuthException) {
    final code = error.code ?? '';
    final status = error.statusCode ?? '';
    final msg = error.message.toLowerCase();
    if (code == 'over_email_send_rate_limit' ||
        msg.contains('email rate limit') ||
        (status == '429' && msg.contains('email'))) {
      return 'Trop d\'emails envoyés en peu de temps. Réessayez dans une '
          'heure, ou contactez l\'assistance sur WhatsApp.';
    }
    if (status == '429' || code == 'over_request_rate_limit') {
      return 'Trop de tentatives. Patientez quelques minutes puis réessayez.';
    }
    if (code == 'invalid_credentials') {
      return 'Email ou mot de passe incorrect.';
    }
    if (code == 'email_not_confirmed') {
      return 'Confirmez d\'abord votre email avec le lien reçu par mail '
          '(pensez aux spams).';
    }
    if (code == 'user_already_exists' || code == 'email_exists') {
      return 'Un compte existe déjà avec cet email : connectez-vous, ou '
          'utilisez « Mot de passe oublié ».';
    }
    if (code == 'weak_password') {
      return 'Mot de passe trop faible : 8 caractères minimum.';
    }
    if (code == 'same_password') {
      return 'Choisissez un mot de passe différent de l\'ancien.';
    }
    if (code == 'otp_expired' || msg.contains('expired')) {
      return 'Le lien a expiré. Demandez-en un nouveau.';
    }
    if (code == 'email_address_invalid' || msg.contains('invalid email')) {
      return 'Adresse email invalide.';
    }
  }
  final text = error.toString().toLowerCase();
  if (text.contains('socketexception') ||
      text.contains('failed to fetch') ||
      text.contains('clientexception') ||
      text.contains('network')) {
    return 'Pas de connexion internet. Vérifiez votre réseau et réessayez.';
  }
  return 'Une erreur est survenue. Réessayez, ou contactez l\'assistance.';
}
