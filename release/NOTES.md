## Stunt Car Racer v71 : robots d'Internet écartés du serveur relais

- Le serveur relais ferme aussitôt toute connexion qui ne commence pas par une inscription du jeu (scanners de ports, requêtes web...) : ces robots n'apparaissent plus dans le tableau des joueurs ni dans le journal, seul le compteur « robots refusés » augmente.
- Une adresse qui revient 3 fois est signalée une seule fois et n'a plus que 3 secondes pour s'inscrire pendant 1 h ; un vrai jeu venant de cette adresse joue normalement.
- Le nombre de joueurs connectés ne compte que les jeux inscrits. Inscription du jeu sous 8 s (au lieu de 20).
- Jeu et serveur relais en v71 (mettre les deux à jour).

### Fichiers
- `StuntCarRacer-win64-v71.zip` : le jeu pour Windows 64 bits (aucune donnée du jeu d'origine : placez votre image disque .st dans `DISK`, voir `LISEZMOI.txt`).
- `ServeurRelaisStuntCar-v71.zip` : le serveur relais pour le multijoueur en ligne (Windows et Linux, même version que le jeu).
