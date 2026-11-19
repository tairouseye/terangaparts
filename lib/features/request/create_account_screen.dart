import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_providers.dart';
import '../../services/auth_service.dart';

/// Encart « Créer mon compte (facultatif) » affiche aux invites.
class GuestAccountCard extends StatelessWidget {
  const GuestAccountCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.person_add_alt_1, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text('Créer mon compte (facultatif)',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 6),
            const Text(
              'Vous êtes en mode invité : vos demandes sont gardées sur cet '
              'appareil. Ajoutez un email pour les retrouver partout et '
              'suivre vos commandes. Vos demandes sont conservées.',
              style: TextStyle(fontSize: 12.5, color: AppColors.gris, height: 1.4),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const CreateAccountScreen())),
              child: const Text('Créer mon compte'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Etape 1 : un invite rattache un email a son compte (meme identifiant,
/// donc memes demandes). Supabase envoie un lien de confirmation.
class CreateAccountScreen extends ConsumerStatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  ConsumerState<CreateAccountScreen> createState() =>
      _CreateAccountScreenState();
}

class _CreateAccountScreenState extends ConsumerState<CreateAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .attachEmail(_email.text.trim(), redirectTo: siteRedirectUrl());
      setState(() => _sent = true);
    } on AuthException catch (e) {
      setState(() => _error = e.message.contains('already')
          ? 'Cet email a déjà un compte : connectez-vous avec lui.'
          : 'Envoi impossible : ${e.message}');
    } catch (_) {
      setState(() => _error = 'Envoi impossible. Réessayez.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer mon compte')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: _sent
                  ? [
                      const Icon(Icons.mark_email_read,
                          color: AppColors.vert, size: 64),
                      const SizedBox(height: 12),
                      Text(
                        'Un lien de confirmation a été envoyé à '
                        '${_email.text.trim()}.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ouvrez-le depuis cet appareil, puis choisissez votre '
                        'mot de passe. Vos demandes restent attachées à votre '
                        'compte.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.gris, height: 1.4),
                      ),
                    ]
                  : [
                      const Text(
                        'Indiquez votre email. Vous recevrez un lien pour le '
                        'confirmer, puis vous choisirez un mot de passe.',
                        style: TextStyle(height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      Form(
                        key: _formKey,
                        child: TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration:
                              const InputDecoration(labelText: 'Email'),
                          validator: (v) {
                            final t = (v ?? '').trim();
                            return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                    .hasMatch(t)
                                ? null
                                : 'Email invalide';
                          },
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(_error!,
                            style: const TextStyle(color: AppColors.danger)),
                      ],
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _sending ? null : _send,
                        child: _sending
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Recevoir le lien'),
                      ),
                    ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Etape 2 : email confirme -> choix du mot de passe (affiche sur l'espace
/// client tant que ce n'est pas fait).
class SetPasswordCard extends ConsumerStatefulWidget {
  const SetPasswordCard({super.key});

  @override
  ConsumerState<SetPasswordCard> createState() => _SetPasswordCardState();
}

class _SetPasswordCardState extends ConsumerState<SetPasswordCard> {
  final _pwd = TextEditingController();
  bool _saving = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _pwd.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_pwd.text.length < 8) {
      setState(() => _error = '8 caractères minimum.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(authServiceProvider).setPassword(_pwd.text);
      setState(() => _done = true);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Enregistrement impossible. Réessayez.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.check_circle, color: AppColors.vert),
          title: Text('Compte créé ! Vous pouvez vous connecter partout.'),
        ),
      );
    }
    return Card(
      color: AppColors.ambre.withValues(alpha: 0.10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dernière étape : choisissez votre mot de passe',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              controller: _pwd,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Mot de passe (8 caractères min.)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.danger)),
            ],
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}
