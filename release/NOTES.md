## Stunt Car Racer v78

**Français**
- Nouveau en v78 : le serveur relais affiche une page web d'état dans un navigateur (parties en cours, joueurs connectés, salles privées ; /status.json en JSON).
- v77 : les menus et messages ajoutés au jeu sont en anglais ; dernière ligne du menu d'options (F1) pour passer en français (langue = fr dans scr.ini).
- v76 : connexion par reverse proxy plus fiable (fermeture WebSocket propre) ; trace réseau du jeu dans scr_reseau.log.
- v75 : la croix de la fenêtre ferme de nouveau le jeu (bloquée depuis la v70).
- Depuis la v74 : quand le serveur est « Hors ligne » par un reverse proxy, le jeu affiche la raison précise (réponse HTTP du proxy, en-tête WebSocket manquant, certificat, DNS, connexion...).
- Le serveur relais peut être placé derrière un reverse proxy web HTTPS (par exemple celui d'un NAS Synology) : le jeu s'y connecte en WebSocket sécurisée (`relais = wss://votre.domaine`), le serveur accepte ces connexions sur son port habituel en plus des connexions directes. Mode d'emploi : `LISEZMOI_SERVEUR.txt`, section 6 (côté Synology, ajouter l'en-tête personnalisé « WebSocket »).
- Le serveur voit la vraie adresse des joueurs derrière le proxy (X-Real-IP / X-Forwarded-For) ; les requêtes web des robots reçoivent un 404 et restent invisibles.
- Toute la documentation (LISEZMOI) a maintenant une version anglaise complète ; les fichiers de réglages sont commentés en français et en anglais.
- Jeu et serveur relais en v78 : mettre les deux à jour.

**English**
- New in v78: the relay server shows a live status web page in a browser (games in progress, connected players, private rooms; /status.json as JSON).
- v77: the menus and messages added to the game are in English; last line of the options menu (F1) switches to French (langue = fr in scr.ini).
- v76: more reliable connection through a reverse proxy (clean WebSocket close); the game's network trace goes to scr_reseau.log.
- v75: the window's close button quits the game again (broken since v70).
- Since v74: when the server shows as offline through a reverse proxy, the game shows the exact reason (proxy HTTP answer, missing WebSocket header, certificate, DNS, connection...).
- The relay server can now sit behind an HTTPS web reverse proxy (for example a Synology NAS): the game connects through a secure WebSocket (`relais = wss://your.domain`); the server accepts these connections on its usual port as well as direct ones. How-to: `LISEZMOI_SERVEUR.txt`, section 6 (on Synology, add the "WebSocket" custom header).
- Behind the proxy the server sees the players' real addresses (X-Real-IP / X-Forwarded-For); robots' web requests get a 404 and stay invisible.
- All readmes (LISEZMOI) now have a full English version; settings files are commented in French and English.
- Game and relay server are both v78: update both.

### Fichiers / Files
- `StuntCarRacer-win64-v78.zip` : le jeu pour Windows 64 bits / the game for 64-bit Windows (no original game data: put your own `.st` disk image in `DISK`, see `LISEZMOI.txt`).
- `ServeurRelaisStuntCar-v78.zip` : le serveur relais (Windows et Linux) / the relay server (Windows and Linux).
