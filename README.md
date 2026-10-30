# ServeurApp Recharge237

App Android installée sur les téléphones serveurs. Elle prend les commandes
en attente dans Firestore (`Transact`), les exécute par USSD sur les SIM
(Orange, MTN, Camtel), lit les SMS opérateurs pour les soldes et publie l'état
du téléphone dans `servers/{deviceId}`. Notifications Telegram après chaque
opération.

Projet Firebase de production : `recharge237-r237` (même base que l'app mobile
et le site Web).

Exploitation des téléphones : voir `docs/EXPLOITATION_TELEPHONES.md`.

Identifiant Android : `com.recharge237.serveur` (avant le 29/10/2026 :
`com.example.projettest`, à désinstaller des téléphones avec
`tools\migrer_identifiant.bat`).
