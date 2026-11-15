# Contrat API — progression par points

Le mobile affiche la progression à partir des points cumulés. Le serveur reste
l'autorité pour attribuer les récompenses, valider les clips et annoncer le
niveau courant. Les seuils dans le mobile (Argent 500, Or 2 000) sont des valeurs
de repli de démonstration ; le backend peut les remplacer dans la réponse.

## `GET /api/me`

Garder les champs de profil existants et fournir ces champs à la racine :

```json
{
  "points": 650,
  "level": "argent",
  "levelThresholds": { "bronze": 0, "argent": 500, "or": 2000 },
  "contributionsValidated": 4
}
```

`points` et `contributionsValidated` sont des entiers cumulés. `level` vaut
`bronze`, `argent` ou `or`. `levelThresholds` est optionnel ; si fourni, il
contient les seuils minimaux en points pour chaque palier. Le mobile tolère son
absence et conserve les seuils de repli.

## `POST /api/clips`

La réponse actuelle `{ clipId, status, reward, licenseTag }` reste compatible.
Pour une mise à jour immédiate de l'interface, `reward` doit désigner les points
accordés par cette action (0 si rejetée). Sont recommandés les champs suivants :

```json
{
  "clipId": "clip_123",
  "status": "peer_review",
  "reward": 150,
  "pointsAdded": 150,
  "pointsTotal": 800,
  "level": "argent",
  "levelUp": { "from": "bronze", "to": "argent" },
  "licenseTag": "commercial"
}
```

`pointsAdded`, `pointsTotal` et `levelUp` sont optionnels. Après une soumission
acceptée, le mobile recharge `GET /api/me`, ce qui garantit que l'affichage du
palier reflète l'état validé par le serveur. Ne jamais utiliser les points
calculés localement pour créditer un compte ou autoriser un retrait.

## Compatibilité

- `level` et `levelThresholds` sont aussi acceptés dans la réponse wallet si
  l'écran des revenus doit fonctionner avant le chargement du profil.
- Les récompenses déjà renvoyées par `/api/validation` et `/api/transcriptions`
  gardent le même modèle : la réponse serveur fait foi ; le mobile rafraîchit le
  profil après les opérations qui modifient le solde.
- Tout changement des valeurs de seuils doit être exposé par `/api/me` afin que
  dashboard, profil et revenus affichent la même progression.
