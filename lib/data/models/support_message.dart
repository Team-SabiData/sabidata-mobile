import 'package:flutter/foundation.dart';

/// Expéditeur d'un message dans le chat d'assistance.
enum MessageSender {
  user,
  bot,
  admin,
  system;

  static MessageSender fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'user':
        return MessageSender.user;
      case 'admin':
        return MessageSender.admin;
      case 'system':
        return MessageSender.system;
      case 'bot':
      default:
        return MessageSender.bot;
    }
  }

  String get key => name;
}

/// Statut de la session de support.
enum SessionStatus {
  active,
  waitingAdmin,
  adminJoined,
  closed;

  static SessionStatus fromString(String? value) {
    switch (value?.toLowerCase()) {
      case 'waiting_admin':
      case 'waitingadmin':
        return SessionStatus.waitingAdmin;
      case 'admin_joined':
      case 'adminjoined':
        return SessionStatus.adminJoined;
      case 'closed':
        return SessionStatus.closed;
      case 'active':
      default:
        return SessionStatus.active;
    }
  }

  String get key {
    switch (this) {
      case SessionStatus.waitingAdmin:
        return 'waiting_admin';
      case SessionStatus.adminJoined:
        return 'admin_joined';
      case SessionStatus.closed:
        return 'closed';
      case SessionStatus.active:
        return 'active';
    }
  }

  String get labelFr {
    switch (this) {
      case SessionStatus.waitingAdmin:
        return 'En attente d\'un administrateur';
      case SessionStatus.adminJoined:
        return 'Administrateur connecté';
      case SessionStatus.closed:
        return 'Session terminée';
      case SessionStatus.active:
        return 'Assistant virtuel actif';
    }
  }
}

/// Message individuel du chat d'assistance.
@immutable
class SupportMessage {
  final String id;
  final String sessionId;
  final MessageSender sender;
  final String text;
  final DateTime createdAt;
  final bool isEscalated;
  final List<String> suggestedReplies;

  const SupportMessage({
    required this.id,
    required this.sessionId,
    required this.sender,
    required this.text,
    required this.createdAt,
    this.isEscalated = false,
    this.suggestedReplies = const [],
  });

  bool get isUser => sender == MessageSender.user;
  bool get isBot => sender == MessageSender.bot;
  bool get isAdmin => sender == MessageSender.admin;
  bool get isSystem => sender == MessageSender.system;

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    final replies = (json['suggestedReplies'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [];

    return SupportMessage(
      id: json['id']?.toString() ?? UniqueKey().toString(),
      sessionId: json['sessionId']?.toString() ?? '',
      sender: MessageSender.fromString(json['sender']?.toString()),
      text: json['text']?.toString() ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isEscalated: json['isEscalated'] == true,
      suggestedReplies: replies,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'sender': sender.key,
        'text': text,
        'createdAt': createdAt.toIso8601String(),
        'isEscalated': isEscalated,
        'suggestedReplies': suggestedReplies,
      };

  SupportMessage copyWith({
    String? id,
    String? sessionId,
    MessageSender? sender,
    String? text,
    DateTime? createdAt,
    bool? isEscalated,
    List<String>? suggestedReplies,
  }) {
    return SupportMessage(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      sender: sender ?? this.sender,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      isEscalated: isEscalated ?? this.isEscalated,
      suggestedReplies: suggestedReplies ?? this.suggestedReplies,
    );
  }
}

/// Session de support contenant le fil de conversation et l'état de relais.
@immutable
class SupportSession {
  final String id;
  final SessionStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? adminName;

  const SupportSession({
    required this.id,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.adminName,
  });

  bool get isEscalated =>
      status == SessionStatus.waitingAdmin || status == SessionStatus.adminJoined;

  factory SupportSession.fromJson(Map<String, dynamic> json) {
    return SupportSession(
      id: json['id']?.toString() ?? 'session_default',
      status: SessionStatus.fromString(json['status']?.toString()),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      adminName: json['adminName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'status': status.key,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (adminName != null) 'adminName': adminName,
      };

  SupportSession copyWith({
    String? id,
    SessionStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? adminName,
  }) {
    return SupportSession(
      id: id ?? this.id,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      adminName: adminName ?? this.adminName,
    );
  }
}
