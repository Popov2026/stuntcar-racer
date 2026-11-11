## Stunt Car Racer v81

**Français**
- Nouveau en v81 : en course à plusieurs, un joueur éliminé (voiture détruite) ou déjà arrivé regarde la suite de la course depuis les tribunes du décor ; flèches gauche / droite : autre voiture, Entrée : menu du groupe.
- v80 : menu Online Multiplayer > « Server status » : parties en cours, joueurs connectés et salles privées du serveur, mis à jour toutes les 5 s (serveur v80 requis).
- v79 : les fichiers LISEZMOI s'appellent maintenant README (README.txt, README_MULTIPLAYER.txt, serveur/README_SERVER.txt...) ; les anciens LISEZMOI d'une version précédente peuvent être supprimés.
- v78 : le serveur relais affiche une page web d'état dans un navigateur (parties en cours, joueurs connectés, salles privées ; /status.json en JSON).
- v77 : les menus et messages ajoutés au jeu sont en anglais ; dernière ligne du menu d'options (F1) pour passer en français (langue = fr dans scr.ini).
- v76 : connexion par reverse proxy plus fiable (fermeture WebSocket propre) ; trace réseau du jeu dans scr_reseau.log.
- v75 : la croix de la fenêtre ferme de nouveau le jeu (bloquée depuis la v70).
- Depuis la v74 : quand le serveur est « Hors ligne » par un reverse proxy, le jeu affiche la raison précise (réponse HTTP du proxy, en-tête WebSocket manquant, certificat, DNS, connexion...).
- Le serveur relais peut être placé derrière un reverse proxy web HTTPS (par exemple celui d'un NAS Synology) : le jeu s'y connecte en WebSocket sécurisée (`relais = wss://votre.domaine`), le serveur accepte ces connexions sur son port habituel en plus des connexions directes. Mode d'emploi : `README_SERVER.txt`, section 6 (côté Synology, ajouter l'en-tête personnalisé « WebSocket »).
- Le serveur voit la vraie adresse des joueurs derrière le proxy (X-Real-IP / X-Forwarded-For) ; les requêtes web des robots reçoivent un 404 et restent invisibles.
- Toute la documentation (README) a maintenant une version anglaise complète ; les fichiers de réglages sont commentés en français et en anglais.
- Jeu et serveur relais en v81 : mettre les deux à jour.

**English**
- New in v81: in multi-car races, a player who is out (car wrecked) or has finished watches the rest of the race from the grandstands of the scenery; left / right arrows: another car, Enter: group menu.
- v80: Online Multiplayer menu > "Server status": the server's games in progress, connected players and private rooms, updated every 5 s (server v80 required).
- v79: the LISEZMOI files are now called README (README.txt, README_MULTIPLAYER.txt, serveur/README_SERVER.txt...); old LISEZMOI files from a previous version can be deleted.
- v78: the relay server shows a live status web page in a browser (games in progress, connected players, private rooms; /status.json as JSON).
- v77: the menus and messages added to the game are in English; last line of the options menu (F1) switches to French (langue = fr in scr.ini).
- v76: more reliable connection through a reverse proxy (clean WebSocket close); the game's network trace goes to scr_reseau.log.
- v75: the window's close button quits the game again (broken since v70).
- Since v74: when the server shows as offline through a reverse proxy, the game shows the exact reason (proxy HTTP answer, missing WebSocket header, certificate, DNS, connection...).
- The relay server can now sit behind an HTTPS web reverse proxy (for example a Synology NAS): the game connects through a secure WebSocket (`relais = wss://your.domain`); the server accepts these connections on its usual port as well as direct ones. How-to: `README_SERVER.txt`, section 6 (on Synology, add the "WebSocket" custom header).
- Behind the proxy the server sees the players' real addresses (X-Real-IP / X-Forwarded-For); robots' web requests get a 404 and stay invisible.
- All readmes (README) now have a full English version; settings files are commented in French and English.
- Game and relay server are both v81: update both.

### Fichiers / Files
- `StuntCarRacer-win64-v81.zip` : le jeu pour Windows 64 bits / the game for 64-bit Windows (no original game data: put your own `.st` disk image in `DISK`, see `README.txt`).
- `ServeurRelaisStuntCar-v81.zip` : le serveur relais (Windows et Linux) / the relay server (Windows and Linux).
