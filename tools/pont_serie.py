#!/usr/bin/env python3
"""pont_serie.py - port série virtuel pour Hatari, relié au serveur relais (jeu en ligne SCRCT60)

Hatari n'émule pas de carte réseau : SCRCT60.PRG peut alors jouer en ligne par le port série
(« transport = serie » dans SCRCT60.INF). Ce pont crée un terminal virtuel (pty) que Hatari prend
comme port série du Falcon (SCC, canal B) et relaie ses octets vers le serveur relais en TCP.
La connexion TCP s'ouvre au premier octet du Falcon (choix « 4. Online Multiplayer » dans le jeu)
et se rouvre au choix suivant si elle a été fermée.

Linux et macOS (Python 3, bibliothèque standard seulement) : terminal virtuel,
« transport = serie » dans SCRCT60.INF

    python3 tools/pont_serie.py                      # serveur officiel
    python3 tools/pont_serie.py --relais hote:27420  # autre serveur relais
    hatari ... --scc-b-in /tmp/scr_falcon_serie --scc-b-out /tmp/scr_falcon_serie

(même chemin pour l'entrée et la sortie : Hatari l'ouvre alors comme un terminal).

Windows (ou partout avec --fichiers) : Hatari n'y relie le port série qu'à des fichiers,
« transport = fichiers » dans SCRCT60.INF (chaque octet en deux lettres A-P) :

    python pont_serie.py --fichiers                  # crée scr_entree.txt et scr_sortie.txt
    hatari ... --scc-b-in scr_entree.txt --scc-b-out scr_sortie.txt

Relancer le pont avant chaque lancement de Hatari (les deux fichiers repartent de zéro).
"""
import argparse, os, select, socket, sys, time

# adresse du serveur officiel, chiffrée comme dans la version PC (jamais affichée)
_OFFI = bytes([0x37, 0x06, 0x07, 0xe2, 0xef, 0xe9, 0xc9, 0xd1, 0xa7, 0xe1, 0xbf, 0x8a])


def official():
    return ''.join(chr(b ^ ((0x5a + 13 * i) & 255)) for i, b in enumerate(_OFFI)), 27420


def say(*a):
    print(time.strftime('%H:%M:%S'), *a, flush=True)


def connect(host, port):
    try:
        sock = socket.create_connection((host, port), timeout=10)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.settimeout(None)
        say('relié au serveur relais')
        return sock
    except OSError as e:
        say('serveur relais injoignable :', e)
        return None             # le Falcon abandonnera (Link abandoned)


def run_pty(a, host, port):
    """Linux, macOS : terminal virtuel, octets bruts."""
    import tty
    master, slave = os.openpty()
    tty.setraw(slave)                       # octets bruts, sans écho ni traduction
    name = os.ttyname(slave)
    try:
        os.unlink(a.port)
    except FileNotFoundError:
        pass
    os.symlink(name, a.port)
    say('port série virtuel :', a.port, '->', name)
    say('Hatari : --scc-b-in %s --scc-b-out %s' % (a.port, a.port))
    say('SCRCT60.INF : transport = serie ; dans le jeu : 4. Online Multiplayer')
    sock = None
    try:
        while True:
            fds = [master] + ([sock] if sock else [])
            r, _, _ = select.select(fds, [], [], 1.0)
            if master in r:
                try:
                    data = os.read(master, 4096)
                except OSError:             # Hatari pas encore (ou plus) branché
                    time.sleep(0.2)
                    continue
                if data and sock is None:
                    sock = connect(host, port)
                if data and sock:
                    try:
                        sock.sendall(data)
                    except OSError:
                        say('connexion coupée (envoi)')
                        sock.close(); sock = None
            if sock and sock in r:
                try:
                    data = sock.recv(4096)
                except OSError:
                    data = b''
                if not data:
                    say('connexion fermée par le serveur')
                    sock.close(); sock = None
                else:
                    os.write(master, data)
    finally:
        try:
            os.unlink(a.port)
        except OSError:
            pass


HEX = b'ABCDEFGHIJKLMNOP'


def run_files(a, host, port):
    """Windows (ou partout) : deux fichiers, chaque octet en deux lettres A-P."""
    import threading
    d = a.fichiers if isinstance(a.fichiers, str) else '.'
    fin, fout = os.path.join(d, 'scr_entree.txt'), os.path.join(d, 'scr_sortie.txt')
    open(fin, 'wb').close()                 # repartent de zéro : relancer le pont avant Hatari
    open(fout, 'wb').close()
    say('fichiers du port série :', os.path.abspath(fin), '(lu par Hatari) et',
        os.path.abspath(fout), '(écrit par Hatari)')
    say('Hatari : --scc-b-in "%s" --scc-b-out "%s"' % (os.path.abspath(fin), os.path.abspath(fout)))
    say('SCRCT60.INF : transport = fichiers ; dans le jeu : 4. Online Multiplayer')
    state = {'sock': None}
    to_falcon = open(fin, 'ab')

    def down(sock):
        while True:
            try:
                data = sock.recv(4096)
            except OSError:
                data = b''
            if not data:
                say('connexion fermée par le serveur')
                if state['sock'] is sock:
                    state['sock'] = None
                return
            out = bytearray()
            for b in data:
                out += HEX[b >> 4:(b >> 4) + 1] + HEX[b & 15:(b & 15) + 1]
            to_falcon.write(out); to_falcon.flush()

    pos, half = 0, -1
    while True:
        try:
            with open(fout, 'rb') as f:
                f.seek(pos)
                chunk = f.read()
        except OSError:
            chunk = b''
        if not chunk:
            time.sleep(0.005)
            continue
        pos += len(chunk)
        data = bytearray()
        for c in chunk:                     # lettres A-P (le reste : ignoré)
            v = c - 65
            if 0 <= v <= 15:
                if half < 0:
                    half = v
                else:
                    data.append((half << 4) | v); half = -1
        if not data:
            continue
        if state['sock'] is None:
            state['sock'] = connect(host, port)
            if state['sock']:
                threading.Thread(target=down, args=(state['sock'],), daemon=True).start()
        if state['sock']:
            try:
                state['sock'].sendall(bytes(data))
            except OSError:
                say('connexion coupée (envoi)')
                state['sock'] = None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--relais', help='serveur relais adresse[:port] (sinon : serveur officiel)')
    ap.add_argument('--port', default='/tmp/scr_falcon_serie', help='lien vers le port série virtuel')
    ap.add_argument('--fichiers', nargs='?', const=True, default=(os.name == 'nt'),
                    help='mode fichiers (Windows) ; dossier facultatif, sinon le dossier courant')
    a = ap.parse_args()
    if a.relais:
        host, _, p = a.relais.partition(':')
        port, shown = int(p or 27420), a.relais
    else:
        (host, port), shown = official(), 'serveur officiel'
    say('serveur relais :', shown)
    try:
        if a.fichiers:
            run_files(a, host, port)
        else:
            run_pty(a, host, port)
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    sys.exit(main())
