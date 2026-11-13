## Stunt Car Racer v95

**Français**
- Nouveau en v95 : serveur relais : positions de course limitées à 100 par seconde et par joueur (un jeu trafiqué ne peut plus saturer la connexion des autres). Relecture de sécurité du serveur et test d'attaque (données au hasard, WebSocket mal formées, inondation) : aucune faille trouvée.
- v94 : sécurité : le jeu vérifie sa disquette (CRC du programme) et refuse une version modifiée ou piégée ; lecture des disquettes et des archives TNT protégée contre les fichiers mal formés (plus aucun dépassement de mémoire possible).
- v93 : lancement « Classique » (--classic) : le look de 1989 en haute résolution fluide, sans textures, sans décor ajouté ni ciel ; bouton Classique de la version navigateur.
- v92 : la version navigateur démarre de nouveau (bloquée en v91). Options de lancement --classic (le jeu de 1989 tel quel) et --modern (version HD avec décor, textures, V8 et foule).
- v91 : le menu « 4. Load/Save/Replay » de la saison marche : la disquette de sauvegarde est le fichier scr_saves.dat, à côté de scr.ini (dans le navigateur : gardé par la page). Quand le jeu demande la disquette de sauvegarde, appuyez sur une touche.
- v90 : vrai son de foule (foule.wav) livré dans le dossier hd et utilisé par la version navigateur. Version navigateur : plus d'option réseau local (le 3e choix du menu de départ est « Online Multiplayer ») ni de circuits TNT.
- v89 : version navigateur, le plein écran (F11, menu F1 ou bouton de la page) montre l'image entière, et Échap revient correctement à la page (avant, on ne voyait plus que la moitié du jeu).
- v88 : page d'accueil de la version navigateur (https://popov2026.github.io/stuntcar-racer/play/) : nombre de joueurs en ligne sur le serveur, disquette ST à fournir, fichier TNT facultatif pour The New Tracks, touches F1 (menu) et F8 (ancien / nouveau).
- v87 : les images HD (cockpit, moteur, flammes, roues, grue) sont livrées dans le dossier hd du jeu et chargées par la version navigateur.
- v86 : la version navigateur démarre directement en HD avec les détails élevés, le décor en densité 2 et le moteur V8 ; l'image .st se glisse sur la page une seule fois, ensuite un clic lance le jeu.
- v85 : version navigateur, sans installation : https://popov2026.github.io/stuntcar-racer/play/ (choisissez votre image .st dans la page ; multijoueur en ligne compris).
- v84 : plus de fichier .bat dans les zips (fausse alerte d'antivirus) ; scr_relay.exe garde lui-même son journal dans scr_relay.log.
- v83 : en détails élevés (F5), le dessus des voitures adverses n'est plus tout rose : moteur V8 texturé à l'emplacement des flammes et pare-brise teinté.
- v82 : « Public room » dans le menu Online Multiplayer, une salle ouverte à tous ; quand une course est lancée dans une salle, les joueurs de la salle qui n'y participent pas la regardent depuis les tribunes (serveur v82 requis).
- v81 : en course à plusieurs, un joueur éliminé (voiture détruite) ou déjà arrivé regarde la suite de la course depuis les tribunes du décor ; flèches gauche / droite : autre voiture, Entrée : menu du groupe.
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
- Jeu et serveur relais en v87 : mettre les deux à jour.

**English**
- New in v95: relay server: race positions limited to 100 per second per player (a tampered game can no longer flood the other players' connections). Security review of the server and attack test (random data, malformed WebSocket, flooding): no flaw found.
- v94: security: the game checks its disk (program CRC) and refuses a modified or booby-trapped version; reading of disks and TNT archives is protected against malformed files (no more possible memory overflow).
- v93: "Classic" launch (--classic): the 1989 look in smooth high resolution, without textures, added scenery or sky; Classic button in the browser version.
- v92: the browser version starts again (blocked in v91). Launch options --classic (the 1989 game as it was) and --modern (HD version with scenery, textures, V8 and crowd).
- v91: the season's "4. Load/Save/Replay" menu works: the save disk is the file scr_saves.dat, next to scr.ini (in the browser: kept by the page). When the game asks for the save disk, press a key.
- v90: real crowd sound (foule.wav) in the hd folder, also used by the browser version. Browser version: no more local network option (the 3rd choice of the start menu is “Online Multiplayer”) and no TNT tracks.
- v89: browser version, full screen (F11, F1 menu or the page's button) shows the whole picture, and Esc goes back to the page properly (before, only half of the game was visible).
- v88: welcome page for the browser version (https://popov2026.github.io/stuntcar-racer/play/): number of players online on the server, ST disk to provide, optional TNT file for The New Tracks, F1 (menu) and F8 (old / new) keys.
- v87: the HD images (cockpit, engine, flames, wheels, crane) come in the game's hd folder and are loaded by the browser version.
- v86: the browser version starts straight in HD with high detail, scenery density 2 and the V8 engine; the .st image is dropped on the page only once, then one click starts the game.
- v85: browser version, nothing to install: https://popov2026.github.io/stuntcar-racer/play/ (choose your .st image in the page; online multiplayer included).
- v84: no more .bat file in the zips (antivirus false alarm); scr_relay.exe keeps its own log in scr_relay.log.
- v83: in high detail (F5), the top of the opponent cars is no longer plain pink: textured V8 engine where the flames come out, and a tinted windscreen.
- v82: "Public room" in the Online Multiplayer menu, a room open to everyone; when a race is started in a room, the players in the room who are not taking part watch it from the grandstands (server v82 required).
- v81: in multi-car races, a player who is out (car wrecked) or has finished watches the rest of the race from the grandstands of the scenery; left / right arrows: another car, Enter: group menu.
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
- Game and relay server are both v87: update both.

### Fichiers / Files
- `StuntCarRacer-win64-v87.zip` : le jeu pour Windows 64 bits / the game for 64-bit Windows (no original game data: put your own `.st` disk image in `DISK`, see `README.txt`).
- `ServeurRelaisStuntCar-v87.zip` : le serveur relais (Windows et Linux) / the relay server (Windows and Linux).
