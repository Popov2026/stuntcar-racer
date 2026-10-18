#!/usr/bin/env python3
"""pont_serie.py - port série virtuel pour Hatari, relié au serveur relais (jeu en ligne SCRCT60)

Hatari n'émule pas de carte réseau : SCRCT60.PRG peut alors jouer en ligne par le port série
(« transport = serie » dans SCRCT60.INF). Ce pont crée un terminal virtuel (pty) que Hatari prend
comme port série du Falcon (SCC, canal B) et relaie ses octets vers le serveur relais en TCP.
La connexion TCP s'ouvre au premier octet du Falcon (choix « 4. Online Multiplayer » dans le jeu)
et se rouvre au choix suivant si elle a été fermée.

Linux et macOS (Python 3, bibliothèque standard seulement) :

    python3 tools/pont_serie.py                      # serveur officiel
    python3 tools/pont_serie.py --relais hote:27420  # autre serveur relais
    hatari ... --scc-b-in /tmp/scr_falcon_serie --scc-b-out /tmp/scr_falcon_serie

(même chemin pour l'entrée et la sortie : Hatari l'ouvre alors comme un terminal).
"""
import argparse, os, select, socket, sys, time, tty

# adresse du serveur officiel, chiffrée comme dans la version PC (jamais affichée)
_OFFI = bytes([0x37, 0x06, 0x07, 0xe2, 0xef, 0xe9, 0xc9, 0xd1, 0xa7, 0xe1, 0xbf, 0x8a])


def official():
    return ''.join(chr(b ^ ((0x5a + 13 * i) & 255)) for i, b in enumerate(_OFFI)), 27420


def say(*a):
    print(time.strftime('%H:%M:%S'), *a, flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--relais', help='serveur relais adresse[:port] (sinon : serveur officiel)')
    ap.add_argument('--port', default='/tmp/scr_falcon_serie', help='lien vers le port série virtuel')
    a = ap.parse_args()
    if a.relais:
        host, _, p = a.relais.partition(':')
        port, shown = int(p or 27420), a.relais
    else:
        (host, port), shown = official(), 'serveur officiel'

    master, slave = os.openpty()
    tty.setraw(slave)                       # octets bruts, sans écho ni traduction
    name = os.ttyname(slave)
    try:
        os.unlink(a.port)
    except FileNotFoundError:
        pass
    os.symlink(name, a.port)
    say('port série virtuel :', a.port, '->', name)
    say('serveur relais :', shown)
    say('Hatari : --scc-b-in %s --scc-b-out %s' % (a.port, a.port))
    say('SCRCT60.INF : transport = serie ; dans le jeu : 4. Online Multiplayer')

    sock, sent, recv = None, 0, 0
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
                    try:
                        sock = socket.create_connection((host, port), timeout=10)
                        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                        sock.settimeout(None)
                        say('relié au serveur relais')
                    except OSError as e:
                        say('serveur relais injoignable :', e)
                        sock = None         # le Falcon abandonnera (Link abandoned)
                if data and sock:
                    try:
                        sock.sendall(data)
                        sent += len(data)
                    except OSError:
                        say('connexion coupée (envoi)')
                        sock.close(); sock = None
            if sock and sock in r:
                try:
                    data = sock.recv(4096)
                except OSError:
                    data = b''
                if not data:
                    say('connexion fermée par le serveur (%d octets envoyés, %d reçus)' % (sent, recv))
                    sock.close(); sock = None
                else:
                    os.write(master, data)
                    recv += len(data)
    except KeyboardInterrupt:
        pass
    finally:
        try:
            os.unlink(a.port)
        except OSError:
            pass


if __name__ == '__main__':
    sys.exit(main())
