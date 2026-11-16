import 'package:flutter_test/flutter_test.dart';
import 'package:sabidata_app/data/models/support_message.dart';
import 'package:sabidata_app/data/api/support_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SupportMessage & SupportSession Models', () {
    test('sérialisation et désérialisation SupportMessage', () {
      final now = DateTime.now();
      final msg = SupportMessage(
        id: 'msg_test_1',
        sessionId: 'sess_123',
        sender: MessageSender.bot,
        text: 'Bonjour, comment puis-je vous aider ?',
        createdAt: now,
        isEscalated: false,
        suggestedReplies: const ['Retrait', 'Enregistrement'],
      );

      final json = msg.toJson();
      expect(json['id'], 'msg_test_1');
      expect(json['sender'], 'bot');
      expect(json['suggestedReplies'], hasLength(2));

      final fromJson = SupportMessage.fromJson(json);
      expect(fromJson.id, msg.id);
      expect(fromJson.isBot, isTrue);
      expect(fromJson.isUser, isFalse);
      expect(fromJson.suggestedReplies, contains('Retrait'));
    });

    test('statuts SupportSession et détection d\'escalade', () {
      final active = SupportSession(
        id: 'sess_1',
        status: SessionStatus.active,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(active.isEscalated, isFalse);

      final waitingAdmin = active.copyWith(status: SessionStatus.waitingAdmin);
      expect(waitingAdmin.isEscalated, isTrue);
      expect(waitingAdmin.status.labelFr, 'En attente d\'un administrateur');

      final adminJoined = active.copyWith(status: SessionStatus.adminJoined);
      expect(adminJoined.isEscalated, isTrue);
    });

    test('désérialisation des expéditeurs variés', () {
      expect(MessageSender.fromString('user'), MessageSender.user);
      expect(MessageSender.fromString('bot'), MessageSender.bot);
      expect(MessageSender.fromString('admin'), MessageSender.admin);
      expect(MessageSender.fromString('system'), MessageSender.system);
      expect(MessageSender.fromString('inconnu'), MessageSender.bot);
    });
  });

  group('SupportApi — Moteur d\'assistance et relais admin', () {
    test('initialisation session de repli avec message d\'accueil', () async {
      final api = SupportApi();
      final data = await api.getCurrentSession();

      expect(data['session'], isA<SupportSession>());
      expect(data['messages'], isNotEmpty);

      final firstMsg = (data['messages'] as List<SupportMessage>).first;
      expect(firstMsg.isBot, isTrue);
      expect(firstMsg.suggestedReplies, isNotEmpty);
    });

    test('réponse immédiate sur question de gains / retraits', () async {
      final api = SupportApi();
      final sessionData = await api.getCurrentSession();
      final session = sessionData['session'] as SupportSession;

      final res = await api.sendMessage(
        sessionId: session.id,
        text: 'Comment faire un retrait de mes FCFA ?',
      );

      final reply = res['replyMessage'] as SupportMessage;
      expect(reply.isBot, isTrue);
      expect(reply.text, contains('5 000 FCFA'));
      expect(reply.text, contains('Orange Money'));
      expect(reply.isEscalated, isFalse);
    });

    test('détection automatique d\'escalade sur demande explicite d\'agent ou administrateur', () async {
      final api = SupportApi();
      final sessionData = await api.getCurrentSession();
      final session = sessionData['session'] as SupportSession;

      final res = await api.sendMessage(
        sessionId: session.id,
        text: 'Je veux parler à un administrateur immédiatement',
      );

      final reply = res['replyMessage'] as SupportMessage;
      expect(reply.isEscalated, isTrue);
      expect(reply.text.toLowerCase(), contains('administrateur'));
    });

    test('escalade manuelle vers l\'administrateur', () async {
      final api = SupportApi();
      final sessionData = await api.getCurrentSession();
      final session = sessionData['session'] as SupportSession;

      final sysMsg = await api.escalateToAdmin(
        sessionId: session.id,
        reason: 'Test escalade manuelle',
      );

      expect(sysMsg.isSystem, isTrue);
      expect(sysMsg.isEscalated, isTrue);
      expect(sysMsg.text, contains('administrateur'));
    });
  });
}
