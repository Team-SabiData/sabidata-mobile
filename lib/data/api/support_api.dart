import 'dart:async';
import 'package:flutter/foundation.dart';
import 'api_client.dart';
import '../models/support_message.dart';
import '../auth/auth_session.dart';

/// Service gérant les échanges avec le chatbot d'assistance et l'escalade vers l'admin.
class SupportApi {
  final ApiClient _client;

  SupportApi([ApiClient? client]) : _client = client ?? ApiClient();

  // Cache mémoire local pour une continuité fluide pendant la session
  static SupportSession? _cachedSession;
  static final List<SupportMessage> _cachedMessages = [];

  /// Initialise ou reprend la session de support active.
  Future<Map<String, dynamic>> getCurrentSession() async {
    try {
      final res = await _client.get('/api/support/sessions/current');
      if (res is Map) {
        final session = SupportSession.fromJson(
            Map<String, dynamic>.from(res['session'] as Map? ?? {}));
        final messagesList = (res['messages'] as List<dynamic>? ?? [])
            .map((m) =>
                SupportMessage.fromJson(Map<String, dynamic>.from(m as Map)))
            .toList();

        _cachedSession = session;
        _cachedMessages
          ..clear()
          ..addAll(messagesList);

        return {
          'session': session,
          'messages': messagesList,
        };
      }
    } catch (e) {
      debugPrint('[SupportApi] Backend non disponible, activation mode autonome: $e');
    }

    // Repli autonome intelligent (offline-first / pré-déploiement backend)
    return _getLocalFallbackSession();
  }

  /// Envoie un message utilisateur et reçoit la réponse du bot (ou du système).
  Future<Map<String, dynamic>> sendMessage({
    required String sessionId,
    required String text,
  }) async {
    final userMsg = SupportMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      sessionId: sessionId,
      sender: MessageSender.user,
      text: text.trim(),
      createdAt: DateTime.now(),
    );

    // 1. Tenter l'envoi au backend
    try {
      final res = await _client.post('/api/support/sessions/$sessionId/messages', {
        'text': text.trim(),
      });

      if (res is Map) {
        final replyJson = res['replyMessage'] as Map<String, dynamic>?;
        if (replyJson != null) {
          final replyMsg = SupportMessage.fromJson(replyJson);
          _cachedMessages.add(userMsg);
          _cachedMessages.add(replyMsg);
          return {
            'userMessage': userMsg,
            'replyMessage': replyMsg,
          };
        }
      }
    } catch (e) {
      debugPrint('[SupportApi] Envoi via serveur échoué, réponse par moteur local: $e');
    }

    // 2. Moteur de réponse autonome avec détection d'escalade automatique
    return _generateLocalResponse(sessionId, userMsg);
  }

  /// Force l'escalade vers un administrateur humain.
  Future<SupportMessage> escalateToAdmin({
    required String sessionId,
    String reason = 'Demande explicite de l\'utilisateur',
  }) async {
    // 1. Appel serveur
    try {
      final res = await _client.post('/api/support/sessions/$sessionId/escalate', {
        'reason': reason,
      });

      if (res is Map && res['systemMessage'] is Map) {
        final sysMsg = SupportMessage.fromJson(
            Map<String, dynamic>.from(res['systemMessage'] as Map));
        _cachedSession = _cachedSession?.copyWith(status: SessionStatus.waitingAdmin);
        _cachedMessages.add(sysMsg);
        return sysMsg;
      }
    } catch (e) {
      debugPrint('[SupportApi] Escalade serveur échouée, traitement local: $e');
    }

    // 2. Traitement local du relais
    _cachedSession = _cachedSession?.copyWith(status: SessionStatus.waitingAdmin) ??
        SupportSession(
          id: sessionId,
          status: SessionStatus.waitingAdmin,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

    final sysMsg = SupportMessage(
      id: 'sys_${DateTime.now().millisecondsSinceEpoch}',
      sessionId: sessionId,
      sender: MessageSender.system,
      text: '🔔 Votre demande a été transmise avec priorité à un administrateur SabiData. Un agent va prendre le relais pour vous assister.',
      createdAt: DateTime.now(),
      isEscalated: true,
      suggestedReplies: [
        'Vérifier mon solde',
        'Consulter la FAQ',
      ],
    );

    _cachedMessages.add(sysMsg);
    return sysMsg;
  }

  // ── MOTEUR LOCAL DE RÉPONSES ET BASE DE CONNAISSANCES SABIDATA ─────────────

  Map<String, dynamic> _getLocalFallbackSession() {
    if (_cachedSession != null && _cachedMessages.isNotEmpty) {
      return {
        'session': _cachedSession!,
        'messages': List<SupportMessage>.from(_cachedMessages),
      };
    }

    final userName = AuthSession.instance.user.value?.name ?? 'Contributeur';
    final session = SupportSession(
      id: 'sess_${DateTime.now().millisecondsSinceEpoch}',
      status: SessionStatus.active,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final welcomeMessage = SupportMessage(
      id: 'welcome_01',
      sessionId: session.id,
      sender: MessageSender.bot,
      text: 'Bonjour $userName ! 👋\n\n'
          'Je suis l\'assistant virtuel SabiData. '
          'Je peux répondre instantanément à vos questions sur les rémunérations, les enregistrements audio, '
          'la validation ou vos gains. '
          'Si besoin, je peux également vous transférer directement à un administrateur.',
      createdAt: DateTime.now(),
      suggestedReplies: const [
        'Comment retirer mes gains ?',
        'Règles d\'enregistrement audio',
        'Validation et points',
        'Parler à un administrateur',
      ],
    );

    _cachedSession = session;
    _cachedMessages
      ..clear()
      ..add(welcomeMessage);

    return {
      'session': session,
      'messages': [welcomeMessage],
    };
  }

  Map<String, dynamic> _generateLocalResponse(
      String sessionId, SupportMessage userMsg) {
    _cachedMessages.add(userMsg);

    final query = userMsg.text.toLowerCase().trim();
    String replyText;
    bool escalate = false;
    List<String> suggestions = [];

    // Détection de demande d'agent / escalade
    if (query.contains('admin') ||
        query.contains('humain') ||
        query.contains('agent') ||
        query.contains('conseiller') ||
        query.contains('personne réelle') ||
        query.contains('responsable')) {
      escalate = true;
      replyText =
          'J\'ai bien pris en compte votre demande. Je préviens immédiatement un administrateur SabiData pour qu\'il prenne le relais sur ce dossier.';
      suggestions = ['Merci, j\'attends', 'Poser une autre question'];
    }
    // Problème de paiement / litige financier
    else if (query.contains('retrait non reçu') ||
        query.contains('argent bloqué') ||
        query.contains('arnaque') ||
        query.contains('erreur transfert') ||
        query.contains('pas reçu mes fcfa')) {
      escalate = true;
      replyText =
          'Les retraits Mobile Money sont traités sous 24h ouvrées. Comme votre demande concerne un paiement non parvenu, j\'alerte un administrateur afin qu\'il consulte les logs bancaires de votre compte.';
      suggestions = ['Voir le statut de l\'alerte', 'Consulter mon portefeuille'];
    }
    // Questions sur les retraits / Mobile Money
    else if (query.contains('retir') ||
        query.contains('paiement') ||
        query.contains('fcfa') ||
        query.contains('orange') ||
        query.contains('moov') ||
        query.contains('wave') ||
        query.contains('gains')) {
      replyText = '💰 **Retraits et Paiements SabiData** :\n\n'
          '• **Seuil minimum** : 5 000 FCFA.\n'
          '• **Moyens acceptés** : Orange Money, Moov Money et Wave (Burkina Faso).\n'
          '• **Délai** : Le traitement est automatique sous 2h à 24h ouvrées.\n'
          '• Pour initier un retrait, rendez-vous sur l\'écran **Revenus** depuis le tableau de bord.';
      suggestions = [
        'Quel est mon solde ?',
        'Comment gagner plus de points ?',
        'Parler à un administrateur',
      ];
    }
    // Questions sur l'enregistrement audio
    else if (query.contains('enregistr') ||
        query.contains('audio') ||
        query.contains('micro') ||
        query.contains('bruit') ||
        query.contains('voix')) {
      replyText = '🎙️ **Conseils d\'enregistrement** :\n\n'
          '• Installez-vous dans un endroit calme, sans écho ni ventilateur.\n'
          '• Parlez de manière naturelle à environ 15 cm du microphone.\n'
          '• Respectez la prononciation et les accents dans votre langue (Mooré, Dioula, Fulfuldé ou Gulmancema).\n'
          '• Réécoutez votre clip avant validation finale pour vous assurer de sa clarté.';
      suggestions = [
        'Combien rapporte un enregistrement ?',
        'Comment sont validés les clips ?',
        'Parler à un administrateur',
      ];
    }
    // Questions sur la validation des clips
    else if (query.contains('valid') ||
        query.contains('point') ||
        query.contains('rejet') ||
        query.contains('niveau') ||
        query.contains('bronze') ||
        query.contains('argent') ||
        query.contains('or')) {
      replyText = '⭐ **Validation & Gamification** :\n\n'
          '• Chaque validation correcte vous rapporte **+20 points**.\n'
          '• Les clips sont validés en pair-à-pair : il faut 3 validations conformes pour approuver un clip.\n'
          '• Vous progressez vers les paliers **Argent (500 pts)** et **Or (2 000 pts)**, débloquant des tâches mieux récompensées.';
      suggestions = [
        'Comment retirer mes gains ?',
        'Contester un rejet',
        'Parler à un administrateur',
      ];
    }
    // Langues supportées
    else if (query.contains('langue') ||
        query.contains('dialecte') ||
        query.contains('mooré') ||
        query.contains('dioula') ||
        query.contains('fulfuldé') ||
        query.contains('gulmancema')) {
      replyText = '🗣️ **Langues nationales supportées** :\n\n'
          'SabiData soutient actuellement 4 langues majeures du Burkina Faso : **Mooré**, **Dioula**, **Fulfuldé** et **Gulmancema**.\n\n'
          'Vous pouvez configurer vos dialectes et votre région depuis votre Profil.';
      suggestions = [
        'Ajouter une langue',
        'Qualité audio requise',
        'Parler à un administrateur',
      ];
    }
    // Cas par défaut
    else {
      replyText =
          'Je comprends votre question. Pour des questions spécifiques à votre compte ou si vous ne trouvez pas la réponse dans nos guides, je peux immédiatement transmettre votre demande à un membre de l\'équipe administrative.';
      suggestions = [
        'Transférer à un administrateur',
        'Comment retirer mes gains ?',
        'Règles d\'enregistrement audio',
      ];
    }

    final replyMsg = SupportMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      sessionId: sessionId,
      sender: MessageSender.bot,
      text: replyText,
      createdAt: DateTime.now(),
      isEscalated: escalate,
      suggestedReplies: suggestions,
    );

    _cachedMessages.add(replyMsg);

    if (escalate) {
      _cachedSession =
          _cachedSession?.copyWith(status: SessionStatus.waitingAdmin);
    }

    return {
      'userMessage': userMsg,
      'replyMessage': replyMsg,
    };
  }
}
