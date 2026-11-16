# Guide d'Implémentation Backend — Module Chatbot & Escalade Admin

Ce document fournit à l'équipe backend toutes les spécifications techniques, les schémas de base de données, les routes d'API, l'intégration IA (Gemini) et les mécanismes d'alerte nécessaires pour brancher le backend au module mobile **Aide & support** de SabiData.

---

## 1. Schéma de Base de Données

Le système repose sur deux entités principales : `support_sessions` et `support_messages`.

### 1.1. Modèle SQL (PostgreSQL / Prisma / TypeORM)

```sql
-- Statuts de la session
CREATE TYPE session_status AS ENUM ('active', 'waiting_admin', 'admin_joined', 'closed');

-- Expéditeur du message
CREATE TYPE message_sender AS ENUM ('user', 'bot', 'admin', 'system');

-- Table des sessions de support
CREATE TABLE support_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status session_status NOT NULL DEFAULT 'active',
    assigned_admin_id UUID REFERENCES users(id) ON DELETE SET NULL,
    escalation_reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Index pour accélérer la recherche des sessions actives de l'utilisateur
CREATE INDEX idx_support_sessions_user_active ON support_sessions(user_id, status);
CREATE INDEX idx_support_sessions_waiting_admin ON support_sessions(status) WHERE status = 'waiting_admin';

-- Table des messages
CREATE TABLE support_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES support_sessions(id) ON DELETE CASCADE,
    sender message_sender NOT NULL,
    sender_id UUID REFERENCES users(id) ON DELETE SET NULL, -- NULL si bot ou system
    text TEXT NOT NULL,
    is_escalated BOOLEAN DEFAULT FALSE,
    suggested_replies JSONB DEFAULT '[]'::jsonb,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_support_messages_session ON support_messages(session_id, created_at ASC);
```

---

## 2. Spécification des Endpoints REST

Tous les endpoints nécessitent une authentification via le jeton Bearer JWT (`Authorization: Bearer <token>`).

### 2.1. Endpoints Utilisateur (Consommés par le Mobile)

| Méthode | Route | Rôle |
| :--- | :--- | :--- |
| `GET` | `/api/support/sessions/current` | Récupère la session active de l'utilisateur (ou en crée une) avec son historique récent. |
| `POST` | `/api/support/sessions/:id/messages` | Envoie un message utilisateur, consulte le moteur IA et renvoie la réponse immédiate. |
| `POST` | `/api/support/sessions/:id/escalate` | Déclenche l'escalade vers l'admin, alerte l'équipe et met à jour le statut. |

#### Exemple d'implémentation de `POST /api/support/sessions/:id/messages` :
1. Valider que `sessionId` appartient bien au `user_id` authentifié.
2. Insérer le message de l'utilisateur dans `support_messages` (`sender: 'user'`).
3. Injecter le contexte de l'utilisateur (nom, solde FCFA, langue principale, statut) dans le prompt IA.
4. Appeler l'API Gemini / LLM.
5. Si l'IA détecte un besoin d'intervention humaine ou si des mots-clés critiques sont présents :
   - Mettre à jour `support_sessions.status = 'waiting_admin'`.
   - Émettre un événement d'alerte admin (Webhook / Notification).
6. Sauvegarder la réponse dans `support_messages` (`sender: 'bot'`).
7. Renvoyer au format attendu par le mobile :
```json
{
  "userMessage": {
    "id": "msg_123",
    "sessionId": "sess_456",
    "sender": "user",
    "text": "Comment retirer mes gains ?",
    "createdAt": "2026-11-16T09:30:00Z"
  },
  "replyMessage": {
    "id": "msg_124",
    "sessionId": "sess_456",
    "sender": "bot",
    "text": "Les retraits se font depuis l'écran Revenus à partir de 5 000 FCFA...",
    "createdAt": "2026-11-16T09:30:01Z",
    "isEscalated": false,
    "suggestedReplies": ["Voir mes revenus", "Parler à un administrateur"]
  }
}
```

---

### 2.2. Endpoints Administration (Backoffice Admin)

| Méthode | Route | Rôle |
| :--- | :--- | :--- |
| `GET` | `/api/admin/support/sessions?status=waiting_admin` | Liste toutes les conversations requérant une intervention humaine. |
| `GET` | `/api/admin/support/sessions/:id` | Détail complet d'une session avec profil utilisateur et historique des messages. |
| `POST` | `/api/admin/support/sessions/:id/reply` | L'administrateur répond à l'utilisateur (`sender: 'admin'`). |
| `POST` | `/api/admin/support/sessions/:id/close` | Clôture la session et repasse le statut à `closed`. |

---

## 3. Configuration du Moteur IA (Gemini 1.5 / 2.0 Flash)

Le modèle **Gemini Flash** est recommandé pour sa vitesse d'inférence (réponse sous 1 seconde) et son coût très faible.

### 3.1. Prompt Système recommandé

```text
Tu es "SabiBot", l'assistant virtuel officiel de l'application mobile SabiData au Burkina Faso.
SabiData est une plateforme de collecte et de validation participative de clips audio en langues nationales (Mooré, Dioula, Fulfuldé, Gulmancema).

RÈGLES MÉTIER SABIDATA :
1. Paiements & Retraits :
   - Seuil minimum de retrait : 5 000 FCFA.
   - Opérateurs supportés : Orange Money, Moov Money, Wave.
   - Délai habituel : de 2h à 24h ouvrées.
   - Les retraits s'initient depuis l'écran "Revenus".
2. Collecte & Audio :
   - Environnement silencieux requis, sans bruit de fond.
   - Parler naturel à ~15 cm du micro.
3. Validation & Gamification :
   - +20 points par validation conforme (3 votes requis par clip).
   - Niveaux : Bronze, Argent (500 pts), Or (2 000 pts).

CONSIGNES DE RÉPONSE :
- Réponds toujours de façon courtoise, concise et claire en français simple (ou en utilisant les termes locaux si pertinent).
- Propose 2 à 3 suggestions de réponses rapides pertinentes au format JSON.
- DÉTECTION D'ESCALADE : Si l'utilisateur conteste un paiement non reçu, se plaint d'un compte bloqué, ou demande expressément à parler à un humain/administrateur, indique `needs_human: true`.

FORMAT DE SORTIE JSON STRICT :
{
  "reply": "Texte de la réponse destinée à l'utilisateur",
  "needs_human": false, // ou true si escalade requise
  "suggested_replies": ["Choix 1", "Choix 2"]
}
```

---

## 4. Système d'Alerte Administrateur

Dès qu'une session passe au statut `waiting_admin` (détection IA ou clic sur *Alerter admin*), le backend doit émettre une alerte instantanée.

### 4.1. Option Webhook Telegram (Simple et Gratuit)

```javascript
// Exemple de fonction d'alerte Telegram dans le backend
async function notifyAdminViaTelegram(session, user, messageText) {
  const botToken = process.env.TELEGRAM_BOT_TOKEN;
  const chatId = process.env.TELEGRAM_ADMIN_CHAT_ID;
  
  const text = `🚨 *ALERTE SUPPORT SABIDATA* 🚨\n\n` +
    `👤 *Utilisateur* : ${user.name} (${user.phone || 'Non renseigné'})\n` +
    `💰 *Solde* : ${user.balance || 0} FCFA | Palier: ${user.level || 'Bronze'}\n` +
    `💬 *Dernier message* : "${messageText}"\n\n` +
    `🔗 [Ouvrir le dossier dans le Dashboard Admin](https://admin.sabidata.org/support/${session.id})`;

  await fetch(`https://api.telegram.org/bot${botToken}/sendMessage`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      chat_id: chatId,
      text: text,
      parse_mode: 'Markdown'
    })
  });
}
```

### 4.2. Option Webhook Discord / Slack
Le backend peut également poster un embed webhook dans le salon `#support-urgent` de l'équipe.

---

## 5. Sécurité & Bonnes Pratiques
* **Vérification de propriété** : Un utilisateur ne doit jamais pouvoir lire ou écrire dans la session d'un autre utilisateur.
* **Rate-limiting** : Limiter à 15 requêtes / minute par IP et par `user_id` sur la route `/api/support/sessions/:id/messages` pour éviter les abus sur l'API LLM.
* **Fallback si l'API IA est indisponible** : Toujours prévoir un message de repli aimable invitant à patienter pendant qu'un administrateur prend en charge la requête.
