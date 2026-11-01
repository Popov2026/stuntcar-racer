## Stunt Car Racer v75

**Français**
- Nouveau en v75 : la croix de la fenêtre ferme de nouveau le jeu (bloquée depuis la v70).
- Depuis la v74 : quand le serveur est « Hors ligne » par un reverse proxy, le jeu affiche la raison précise (réponse HTTP du proxy, en-tête WebSocket manquant, certificat, DNS, connexion...).
- Le serveur relais peut être placé derrière un reverse proxy web HTTPS (par exemple celui d'un NAS Synology) : le jeu s'y connecte en WebSocket sécurisée (`relais = wss://votre.domaine`), le serveur accepte ces connexions sur son port habituel en plus des connexions directes. Mode d'emploi : `LISEZMOI_SERVEUR.txt`, section 6 (côté Synology, ajouter l'en-tête personnalisé « WebSocket »).
- Le serveur voit la vraie adresse des joueurs derrière le proxy (X-Real-IP / X-Forwarded-For) ; les requêtes web des robots reçoivent un 404 et restent invisibles.
- Toute la documentation (LISEZMOI) a maintenant une version anglaise complète ; les fichiers de réglages sont commentés en français et en anglais.
- Jeu et serveur relais en v75 : mettre les deux à jour.

**English**
- New in v75: the window's close button quits the game again (broken since v70).
- Since v74: when the server shows as offline through a reverse proxy, the game shows the exact reason (proxy HTTP answer, missing WebSocket header, certificate, DNS, connection...).
- The relay server can now sit behind an HTTPS web reverse proxy (for example a Synology NAS): the game connects through a secure WebSocket (`relais = wss://your.domain`); the server accepts these connections on its usual port as well as direct ones. How-to: `LISEZMOI_SERVEUR.txt`, section 6 (on Synology, add the "WebSocket" custom header).
- Behind the proxy the server sees the players' real addresses (X-Real-IP / X-Forwarded-For); robots' web requests get a 404 and stay invisible.
- All readmes (LISEZMOI) now have a full English version; settings files are commented in French and English.
- Game and relay server are both v75: update both.

### Fichiers / Files
- `StuntCarRacer-win64-v75.zip` : le jeu pour Windows 64 bits / the game for 64-bit Windows (no original game data: put your own `.st` disk image in `DISK`, see `LISEZMOI.txt`).
- `ServeurRelaisStuntCar-v75.zip` : le serveur relais (Windows et Linux) / the relay server (Windows and Linux).
