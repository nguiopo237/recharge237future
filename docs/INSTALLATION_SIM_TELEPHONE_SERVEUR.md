# Installer une nouvelle SIM dans un téléphone serveur

Manuel opérateur — Recharge237 ServeurApp. Il couvre MTN, Orange et CAMTEL
(prépayé et postpayé) : la procédure est **identique** pour les trois, seule la
valeur choisie dans la liste des opérateurs change.

Durée réelle : **5 à 10 minutes** par téléphone, dont l'essentiel est
l'attente de la détection côté application.

---

## 0. Ce qu'il faut avoir sous la main

- Le PIN de la carte SIM (4 chiffres, celui de l'opérateur — pas le code de
  déverrouillage du téléphone).
- Le numéro de la carte (utile pour un essai de recharge à 100 F).
- Le téléphone serveur allumé, connecté à Internet (Wi-Fi ou données).
- L'application d'administration Recharge237 sur **votre** téléphone, avec un
  compte `isadmin = true`.

---

## 1. Sur le téléphone serveur

1. **Insérer la carte** dans l'emplacement voulu. Retenez le numéro physique :
   **SIM 1 = emplacement 0**, SIM 2 = emplacement 1 (c'est cette numérotation
   que l'application admin affiche).
2. **Redémarrer le téléphone** après l'insertion. C'est ce qui force le modem à
   relire la carte ; sans redémarrage, la détection reste parfois sur l'ancienne
   carte pendant plusieurs minutes.
3. **Paramètres → SIM** : activer la carte, laisser la sélection d'opérateur en
   **automatique**. Vérifier que les **données mobiles** ou le **Wi-Fi** sont
   actifs : sans Internet, l'application ne publie rien et ne reçoit aucune
   commande.
4. **Lancer ServeurApp Recharge237** et attendre ~20 secondes. Le téléphone
   publie alors dans la base son modèle, ses cartes détectées (`sims`) et
   l'heure de détection.
   > **Téléphone neuf ou APK réinstallé** : son identité anonyme n'a pas encore
   > le droit d'écrire. L'application demande elle-même son autorisation ;
   > dans l'application d'administration, écran **Serveurs**, appuyez sur
   > **Autoriser** sur la ligne en attente. Rien à saisir sur le téléphone.
5. **Autorisation d'accessibilité** (elle saute parfois après une mise à jour de
   l'APK) : *Paramètres → Accessibilité → Recharge237 ServeurApp* → activer.
   Sans elle, aucun écran USSD n'est lu ni rempli.
6. **Batterie** : *Paramètres → Applications → Recharge237 ServeurApp →
   Batterie* → **Sans restriction**.
7. **MIUI / HyperOS uniquement** : *Sécurité → Autorisations → Démarrage auto*
   → autoriser Recharge237, sinon le système tue le service en veille.

---

## 2. Dans l'application d'administration

8. **Tableau de bord → Serveurs USSD** → toucher le téléphone concerné
   (identifié par son nom et son modèle).
9. Chaque emplacement affiche déjà **« détecté : MTN / Orange / CAMTEL »**.
   L'application pré-remplit donc l'opérateur à partir de la carte réellement
   présente : vous n'avez rien à deviner.
10. Pour **chaque** emplacement utilisé :
    - **Opérateur** : MTN, Orange, CAMTEL prépayé, CAMTEL postpayé, ou *Libre* ;
    - **PIN de la carte** : celui de cette SIM ;
    - **Actif** : cocher (un emplacement non coché n'est jamais utilisé, même
      si la carte est présente) ;
    - **Seuil de solde** (facultatif) : alerte Telegram quand le solde lu par
      SMS passe dessous.
11. **Enregistrer.** Le téléphone applique la configuration **dans la seconde** :
    il écoute son document et recharge ses PIN et son routage tout seul. Le
    bouton *Recharger la configuration* n'est qu'un secours si le téléphone
    était hors ligne au moment de l'enregistrement.

---

## 3. Contrôles avant de dire « c'est prêt »

12. Dans la fiche serveur, les lignes doivent afficher :
    - **Réseau** : « toutes les SIM enregistrées », état `IN_SERVICE` ;
    - **SIM … : PIN enregistré** ;
    - **Routage** : `mtn_airtime, mtn_forfait, mtn_forfait_activate` (MTN) ou
      `orange_airtime` (Orange) ou `camtel_pre, camtel_post` (CAMTEL).
13. **Essai gratuit** (aucun débit, aucun PIN) : lancement d'une consultation
    d'offres MTN Boost / Orange Good Deal sur un numéro de test. On doit
    recevoir la liste des offres **avec leurs prix** en quelques secondes.
14. **Essai payant** (facultatif) : une recharge de 100 F sur un numéro de test.
    La commande doit finir en statut 34 (livrée).
15. **Telegram** : vous devez recevoir le message de démarrage du serveur et,
    plus tard, toute alerte de perte de réseau ou de changement de carte.

---

## 4. Règles à ne jamais enfreindre

- **Un emplacement = un opérateur.** Deux cartes du même opérateur dans les
  deux emplacements ne servent à rien : le routage n'en utilise qu'une.
- **Le PIN doit être celui de la carte de cet emplacement.** Un PIN d'une autre
  carte produit des échecs « Code PIN incorrect » à répétition.
- **Deux cartes CAMTEL** : la carte du plus petit emplacement est la
  **prépayée**, la suivante la **postpayée**. C'est automatique si vous laissez
  faire la détection ; si vous forcez l'emplacement, respectez cet ordre.
- **CAMTEL n'accepte que des numéros CAMTEL** (`62…`) : une commande CAMTEL vers
  un numéro MTN est ignorée, jamais exécutée.
- **Après une permutation de puces** entre deux téléphones, re-déclarez les deux
  emplacements. Sans cela, une commande peut partir sur la mauvaise carte — la
  garde réseau la bloquera, mais elle sera perdue pour le client.
- **Emplacement « Libre »** = carte ignorée par le serveur. À utiliser quand une
  carte est présente mais ne doit rien vendre (carte de secours, carte en
  test).
- **Un téléphone ne prend que ce qu'il peut livrer** : si vous assignez un type
  que sa carte ne permet pas, la fiche le signale en rouge et les commandes
  resteront bloquées.

---

## 5. En cas de problème

| Symptôme | Cause la plus fréquente | Ce qu'il faut faire |
|---|---|---|
| La fiche serveur reste muette | Application arrêtée, ou pas d'Internet | Relancer l'app ; vérifier Wi-Fi/données depuis le téléphone |
| « Aucune SIM détectée » | Carte mal insérée, ou téléphone non redémarré | Réinsérer, redémarrer |
| Réseau `OUT_OF_SERVICE` | Opérateur momentanément indisponible | Attendre : le serveur tente un cycle réseau lui-même (mode avion 35 s, Wi-Fi et données rendus ensuite) |
| « PIN MANQUANT » | PIN non saisi pour cet emplacement | Le saisir dans l'écran des emplacements |
| « Code PIN incorrect » sur chaque vente | PIN d'une autre carte | Corriger le PIN de l'emplacement concerné |
| Offres visibles mais activation en échec « offre à X F non proposée » | MTN a changé son menu entre la consultation et l'achat | Relancer la consultation des offres, puis l'achat |
| Aucune commande ne part | Emplacement non coché « actif », ou routage vide | Cocher l'emplacement, enregistrer |
