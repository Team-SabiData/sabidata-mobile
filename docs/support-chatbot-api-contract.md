# Contrat API — Chatbot Support & Escalade Admin

Ce document définit les spécifications des endpoints backend pour le module de support interactif et la prise de relais par un administrateur dans **SabiData**.

---

## 1. Modèle de Données

### Session de Support (`SupportSession`)
```json
{
  "id": "sess_98234",
  "userId": "usr_42",
  "userName": "Adama Ouédraogo",
  "userPhone": "+22670112233",
  "status": "active", // "active" | "waiting_admin" | "admin_joined" | "closed"
  "createdAt": "2026-11-16T09:00:00Z",
  "updatedAt": "2026-11-16T09:05:00Z",
  "adminId": null,
  "adminName": null
}
```

### Message (`SupportMessage`)
```json
{
  "id": "msg_101",
  "sessionId": "sess_98234",
  "sender": "bot", // "user" | "bot" | "admin" | "system"
  "text": "Bonjour Adama ! Je suis SabiBot. Comment puis-je vous aider aujourd'hui ?",
  "createdAt": "2026-11-16T09:00:05Z",
  "isEscalated": false,
  "suggestedReplies": [
    "Comment retirer mes FCFA ?",
    "Règles d'enregistrement audio",
    "Validation et récompenses",
    "Parler à un conseiller humain"
  ]
}
```

---

## 2. Endpoints Utilisateur (Mobile)

### 2.1. Initialiser ou reprendre la session courante
* **Méthode** : `GET /api/support/sessions/current`
* **Headers** : `Authorization: Bearer <jwt_token>`
* **Réponse 200** :
```json
{
  "session": {
    "id": "sess_98234",
    "status": "active"
  },
  "messages": [
    {
      "id": "msg_001",
      "sessionId": "sess_98234",
      "sender": "bot",
      "text": "Bonjour ! Je suis SabiBot, votre assistant virtuel SabiData. Une question sur vos enregistrements, vos gains ou votre compte ?",
      "createdAt": "2026-11-16T09:00:00Z",
      "suggestedReplies": [
        "Retrait de mes gains",
        "Qualité audio requise",
        "Points et niveaux",
        "Parler à un humain"
      ]
    }
  ]
}
```

### 2.2. Envoyer un message & Obtenir la réponse immédiate
* **Méthode** : `POST /api/support/sessions/:id/messages`
* **Headers** : `Authorization: Bearer <jwt_token>`, `Content-Type: application/json`
* **Body** :
```json
{
  "text": "Pourquoi mon retrait Orange Money de ce matin n'est pas encore arrivé ?"
}
```
* **Réponse 200 (si le bot répond ou s'il déclenche l'escalade)** :
```json
{
  "userMessage": {
    "id": "msg_102",
    "sessionId": "sess_98234",
    "sender": "user",
    "text": "Pourquoi mon retrait Orange Money de ce matin n'est pas encore arrivé ?",
    "createdAt": "2026-11-16T09:01:10Z"
  },
  "replyMessage": {
    "id": "msg_103",
    "sessionId": "sess_98234",
    "sender": "bot",
    "text": "Les retraits Mobile Money sont généralement traités sous 2 à 24 heures ouvrées. Si votre transaction dépasse 24h ou présente une erreur, un administrateur peut vérifier votre historique.",
    "createdAt": "2026-11-16T09:01:12Z",
    "isEscalated": false,
    "suggestedReplies": [
      "Vérifier mon historique",
      "Demander à un administrateur"
    ]
  }
}
```

### 2.3. Déclencher une escalade vers l'administrateur
* **Méthode** : `POST /api/support/sessions/:id/escalate`
* **Headers** : `Authorization: Bearer <jwt_token>`, `Content-Type: application/json`
* **Body** :
```json
{
  "reason": "user_requested", // ou "bot_confusion", "payment_dispute"
  "lastMessage": "Je souhaite parler à un administrateur pour débloquer mon solde."
}
```
* **Réponse 200** :
```json
{
  "status": "waiting_admin",
  "systemMessage": {
    "id": "msg_104",
    "sessionId": "sess_98234",
    "sender": "system",
    "text": "Votre demande a été transmise à un administrateur SabiData. Un membre de l'équipe prendra le relais dès que possible.",
    "createdAt": "2026-11-16T09:02:00Z",
    "isEscalated": true
  }
}
```

---

## 3. Webhook & Notification Administrateur

Lorsqu'une session est escaladée, le serveur déclenche un événement (Webhook, Push ou Email) à destination de l'équipe support :

```json
{
  "event": "support.escalation_requested",
  "timestamp": "2026-11-16T09:02:00Z",
  "session": {
    "sessionId": "sess_98234",
    "userId": "usr_42",
    "userName": "Adama Ouédraogo",
    "userPhone": "+22670112233",
    "userLevel": "argent",
    "walletBalance": 12500
  },
  "reason": "payment_dispute",
  "summary": "Problème sur un retrait Mobile Money en attente.",
  "adminDashboardUrl": "https://admin.sabidata.org/support/sessions/sess_98234"
}
```
