import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../widgets/motif_header.dart';
import '../widgets/app_body.dart';
import '../widgets/app_feedback.dart';
import '../data/models/support_message.dart';
import '../data/api/support_api.dart';

/// Écran d'Aide & Support intégrant le chatbot SabiBot et l'escalade vers l'administrateur.
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final SupportApi _api = SupportApi();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  SupportSession? _session;
  final List<SupportMessage> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSession() async {
    setState(() => _isLoading = true);
    try {
      final data = await _api.getCurrentSession();
      if (mounted) {
        setState(() {
          _session = data['session'] as SupportSession?;
          final msgs = data['messages'] as List<SupportMessage>? ?? [];
          _messages
            ..clear()
            ..addAll(msgs);
          _isLoading = false;
        });
        _scrollToBottom();
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage([String? textToSend]) async {
    final text = textToSend ?? _inputController.text;
    if (text.trim().isEmpty || _isSending) return;

    if (textToSend == null) {
      _inputController.clear();
    }

    final currentSessionId = _session?.id ?? 'sess_temp';

    // Ajout optimiste du message utilisateur
    final optimisticMsg = SupportMessage(
      id: 'optimistic_${DateTime.now().millisecondsSinceEpoch}',
      sessionId: currentSessionId,
      sender: MessageSender.user,
      text: text.trim(),
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(optimisticMsg);
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final res = await _api.sendMessage(
        sessionId: currentSessionId,
        text: text.trim(),
      );

      if (mounted) {
        final replyMsg = res['replyMessage'] as SupportMessage?;
        setState(() {
          _isSending = false;
          // Remplace le message optimiste si l'ID a changé
          if (replyMsg != null) {
            final idx = _messages.indexWhere((m) => m.id == optimisticMsg.id);
            if (idx != -1 && res['userMessage'] is SupportMessage) {
              _messages[idx] = res['userMessage'] as SupportMessage;
            }
            if (!_messages.any((m) => m.id == replyMsg.id)) {
              _messages.add(replyMsg);
            }
            if (replyMsg.isEscalated) {
              _session = _session?.copyWith(status: SessionStatus.waitingAdmin);
            }
          }
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        showAppSnack(context, 'Impossible d\'envoyer le message. Réessayez.');
      }
    }
  }

  Future<void> _escalateToAdmin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: const [
            Icon(Icons.support_agent_rounded, color: AppColors.primary, size: 28),
            SizedBox(width: 10),
            Text('Alerter un administrateur',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
        content: const Text(
          'Votre demande et l\'historique de la conversation seront envoyés avec priorité à l\'équipe SabiData. Un administrateur reprendra le relais directement.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirmer l\'alerte'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSending = true);
    try {
      final sysMsg = await _api.escalateToAdmin(
        sessionId: _session?.id ?? 'sess_default',
        reason: 'Demande explicite de transfert humain',
      );

      if (mounted) {
        setState(() {
          _isSending = false;
          _session = _session?.copyWith(status: SessionStatus.waitingAdmin);
          if (!_messages.any((m) => m.id == sysMsg.id)) {
            _messages.add(sysMsg);
          }
        });
        _scrollToBottom();
        showAppSnack(context, 'L\'administrateur a été alerté avec succès.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSending = false);
        showAppSnack(context, 'Erreur lors de l\'alerte admin.');
      }
    }
  }

  List<String> get _latestSuggestions {
    if (_messages.isEmpty) return [];
    final lastBotMsg = _messages.lastWhere(
      (m) => m.isBot || m.isSystem,
      orElse: () => _messages.last,
    );
    return lastBotMsg.suggestedReplies;
  }

  bool get _isEscalated =>
      _session?.status == SessionStatus.waitingAdmin ||
      _session?.status == SessionStatus.adminJoined;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: AppBody(
        child: Column(
          children: [
            // En-tête textile SabiData
            MotifHeader(
              motif: 'assets/motifs/motif_voix.png',
              title: 'Aide & support',
              subtitle: _isEscalated ? 'Relais administrateur en cours' : 'Assistant virtuel 24/7',
              height: 136,
              onBack: () => context.pop(),
              trailing: GestureDetector(
                onTap: _escalateToAdmin,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isEscalated
                        ? AppColors.gold.withValues(alpha: 0.25)
                        : Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isEscalated ? AppColors.gold : Colors.white.withValues(alpha: 0.35),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isEscalated ? Icons.admin_panel_settings_rounded : Icons.support_agent_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isEscalated ? 'Admin alerté' : 'Alerter admin',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Bannière d'alerte si escaladé
            if (_isEscalated)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.goldSoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active_rounded, color: AppColors.gold, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Un administrateur a été notifié et consultera votre dossier.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.gold),
                      ),
                    ),
                  ],
                ),
              ),

            // Liste des messages
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: _messages.length + (_isSending ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length && _isSending) {
                          return _buildTypingIndicator();
                        }
                        return _buildMessageItem(_messages[index]);
                      },
                    ),
            ),

            // Suggestions de réponses rapides (Chips horizontaux)
            if (!_isSending && _latestSuggestions.isNotEmpty)
              Container(
                height: 44,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: _latestSuggestions.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final suggestion = _latestSuggestions[index];
                    return ActionChip(
                      label: Text(
                        suggestion,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                      ),
                      backgroundColor: AppColors.primarySoft,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      onPressed: () => _sendMessage(suggestion),
                    );
                  },
                ),
              ),

            // Barre de saisie
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageItem(SupportMessage msg) {
    if (msg.isSystem) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.goldSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
          ),
          child: Text(
            msg.text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.gold),
          ),
        ),
      );
    }

    if (msg.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const SizedBox(width: 48),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE11D28), Color(0xFFC41620)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(18),
                    bottomRight: Radius.circular(4),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  msg.text,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white, height: 1.35),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Messages du Bot ou de l'Admin
    final isAdmin = msg.isAdmin;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isAdmin ? AppColors.blue.withValues(alpha: 0.15) : AppColors.primarySoft,
              shape: BoxShape.circle,
              border: Border.all(
                color: isAdmin ? AppColors.blue : AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Icon(
              isAdmin ? Icons.support_agent_rounded : Icons.smart_toy_rounded,
              size: 18,
              color: isAdmin ? AppColors.blue : AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          // Bulle
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
                border: Border.all(
                  color: isAdmin ? AppColors.blue.withValues(alpha: 0.4) : AppColors.border,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isAdmin ? 'Administrateur SabiData' : 'SabiBot',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: isAdmin ? AppColors.blue : AppColors.primary,
                          letterSpacing: 0.3,
                        ),
                      ),
                      if (isAdmin) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded, size: 13, color: AppColors.blue),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    msg.text,
                    style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 32),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.smart_toy_rounded, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                ),
                SizedBox(width: 10),
                Text('SabiBot vous répond...',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Champ texte
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _inputController,
                  focusNode: _focusNode,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
                  decoration: const InputDecoration(
                    hintText: 'Posez votre question...',
                    hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 14),
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (val) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),

            // Bouton d'envoi
            GestureDetector(
              onTap: () => _sendMessage(),
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFE11D28), Color(0xFFC41620)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
