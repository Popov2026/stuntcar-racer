## Stunt Car Racer v73

**Français**
- Le serveur relais peut être placé derrière un reverse proxy web HTTPS (par exemple celui d'un NAS Synology) : le jeu s'y connecte en WebSocket sécurisée (`relais = wss://votre.domaine`), le serveur accepte ces connexions sur son port habituel en plus des connexions directes. Mode d'emploi : `LISEZMOI_SERVEUR.txt`, section 6 (côté Synology, ajouter l'en-tête personnalisé « WebSocket »).
- Le serveur voit la vraie adresse des joueurs derrière le proxy (X-Real-IP / X-Forwarded-For) ; les requêtes web des robots reçoivent un 404 et restent invisibles.
- Toute la documentation (LISEZMOI) a maintenant une version anglaise complète ; les fichiers de réglages sont commentés en français et en anglais.
- Jeu et serveur relais en v73 : mettre les deux à jour.

**English**
- The relay server can now sit behind an HTTPS web reverse proxy (for example a Synology NAS): the game connects through a secure WebSocket (`relais = wss://your.domain`); the server accepts these connections on its usual port as well as direct ones. How-to: `LISEZMOI_SERVEUR.txt`, section 6 (on Synology, add the "WebSocket" custom header).
- Behind the proxy the server sees the players' real addresses (X-Real-IP / X-Forwarded-For); robots' web requests get a 404 and stay invisible.
- All readmes (LISEZMOI) now have a full English version; settings files are commented in French and English.
- Game and relay server are both v73: update both.

### Fichiers / Files
- `StuntCarRacer-win64-v73.zip` : le jeu pour Windows 64 bits / the game for 64-bit Windows (no original game data: put your own `.st` disk image in `DISK`, see `LISEZMOI.txt`).
- `ServeurRelaisStuntCar-v73.zip` : le serveur relais (Windows et Linux) / the relay server (Windows and Linux).
