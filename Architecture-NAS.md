# Architecture du NAS

État vérifié le **11 novembre 2026**.

Ce document décrit l'architecture, les ports, les dossiers et l'emplacement des
configurations. Il ne contient **aucun mot de passe ni jeton**, et ne constitue
pas une sauvegarde des configurations, des photos, des bases ou des disques de VM.

## 1. Vue d'ensemble

- **NAS** : `nas`, adresse LAN `192.168.100.36` **fixe** (statique dans
  `/etc/netplan/00-installer-config.yaml` et réservée dans le DHCP UniFi pour
  la MAC `1c:83:41:41:93:e1`). Auparavant obtenue par DHCP sans réservation,
  elle était passée à `.34` après un redémarrage le 12 novembre 2026.
- **Administration SSH** : utilisateur `benjamin`, avec accès Docker et sudo.
- **Stockage** : RAID monté sur `/mnt/raid1`, périphérique `/dev/md0`, format ext4.
  **⚠ RAID 1 dégradé** : seul le disque Seagate `ST8000NE0001` (série `ZA13R8KJ`)
  est présent ; le second disque n'est plus détecté (port SATA `ata1` « link
  down ») depuis au moins le 11 novembre 2026. Aucune redondance tant qu'il n'est
  pas remplacé ou reconnecté, puis réintégré avec `mdadm --add`. `mdmonitor` est
  en échec faute d'adresse d'alerte dans `/etc/mdadm/mdadm.conf` : la panne
  n'a donc pas été signalée.
- **Docker Compose** : trois projets indépendants, `plex`, `immich`, `downloads`.
- **Home Assistant** : VM KVM/QEMU gérée par libvirt, et non conteneur Docker.
- **Samba** : un seul partage de fichiers, `/mnt/raid1/samba`.
- **Cockpit** : interface d'administration du NAS.

```text
Réseau local
|
+-- NAS : 192.168.100.36
|   |
|   +-- SSH / Cockpit : administration
|   +-- Samba : /mnt/raid1/samba
|   |
|   +-- Docker
|       +-- Plex -------------------- lit /mnt/raid1/samba
|       +-- AriaNg --> Aria2 -------- écrit /mnt/raid1/samba
|       +-- Immich
|           +-- serveur ------------ photos sur le RAID
|           +-- PostgreSQL --------- base sur le RAID
|           +-- Valkey ------------- cache interne
|           +-- machine-learning --- cache de modèles Docker
|
+-- VM Home Assistant : 192.168.100.21
    +-- réseau relié au LAN via le pont br0 du NAS
    +-- disque stocké dans /mnt/raid1/vms
```

## 2. Interfaces et ports

### Accès utilisateur et administration

| Élément | Adresse / accès | Port et protocole | Remarques |
| --- | --- | --- | --- |
| SSH du NAS | `ssh benjamin@192.168.100.36` | TCP 22 | Administration en ligne de commande |
| Cockpit | <https://192.168.100.36:9090> | TCP 9090 | Administration web ; certificat local possible |
| Plex | <http://192.168.100.36:32400/web> | TCP 32400 | Interface web et diffusion des médias |
| Immich | <http://192.168.100.36:2283> | TCP 2283 | Interface photos et API |
| AriaNg | <http://192.168.100.36:6880> | TCP 6880 | Interface web de téléchargement |
| Aria2 RPC | `http://192.168.100.36:6800/jsonrpc` | TCP 6800 | API commandant Aria2 ; secret RPC obligatoire |
| Samba | `\\192.168.100.36\samba` | TCP 445 | Seul partage de fichiers utilisateur |
| Samba / NetBIOS | NAS | TCP 139, UDP 137 et 138 | Compatibilité et découverte réseau |
| Home Assistant | <http://192.168.100.21:8123> | TCP 8123 | Adresse de la VM, différente de celle du NAS ; HTTP 200 vérifié |
| Console VNC de la VM | NAS, affichage `:0` | TCP 5900 | Console QEMU existante ; écoute observée sur toutes les interfaces IPv4 |

### Ports internes et découverte

| Élément | Ports | Portée |
| --- | --- | --- |
| PostgreSQL Immich | TCP 5432 | Réseau Docker `immich_default`, non publié sur le NAS |
| Valkey Immich | TCP 6379 | Réseau Docker `immich_default`, non publié sur le NAS |
| Machine-learning Immich | API interne | Non publiée sur le NAS ; communication entre conteneurs |
| Découverte Plex | UDP 32410, 32412, 32413, 32414 | Écoutes observées sur le NAS |
| Autre écoute Plex observée | UDP 1901 | Écoute présente ; pas une interface utilisateur |
| Services auxiliaires Plex | TCP 32401 et 32600 | Écoutes observées sur `127.0.0.1` uniquement |
| Réseau virtuel libvirt `default` | TCP/UDP 53, UDP 67 | DNS/DHCP du réseau virtuel `192.168.122.0/24` |
| Client DHCP du NAS | UDP 68 | Sur le pont LAN `br0` |
| Aria2 BitTorrent | 6888 TCP/UDP indiqué dans l'image | **Non publié** ; aucun port torrent ajouté pour cette installation HTTP/HTTPS |

Plex utilise le **réseau hôte** : ses ports ne figurent pas comme redirections
Docker. Immich utilise un réseau Docker privé avec seulement TCP 2283 publié.
Aria2 et AriaNg utilisent `downloads_default`, avec TCP 6800 et 6880 publiés
explicitement sur `192.168.100.36`.

Les adresses IP de conteneurs et certains ports auxiliaires sont dynamiques :
ils ne doivent pas être utilisés comme points d'accès permanents.

**Accès externe :** depuis le 11 novembre 2026, seule la redirection WAN
TCP 443 vers la VM proxy `192.168.30.10` est configurée (voir section 2bis).
Plex peut toutefois ouvrir ses propres ports via UPnP.
Ne pas publier Samba, VNC ou Aria2 RPC sur Internet ; préférer un VPN.
AriaNg et Aria2 utilisent HTTP sur le LAN, sans chiffrement du transport.

## 2bis. Proxy inverse isolé (DMZ) — mis en place le 11 novembre 2026

Toutes les requêtes HTTPS entrantes passent par une **VM proxy dédiée**,
isolée dans un VLAN DMZ. Home Assistant ne reçoit plus de trafic Internet direct.

```text
Internet -- TCP 443 --> UniFi (DNAT) --> VM proxy 192.168.30.10 (VLAN 30, zone DMZ)
                                            +--> HA        192.168.100.21:8123
                                            +--> Immich    192.168.100.36:2283
                                            +--> Plex      192.168.100.36:32400 (privé)
                                            +--> AriaNg    192.168.100.36:6880  (privé)
                                            +--> Aria2 RPC 192.168.100.36:6800  (privé, /jsonrpc)
                                            +--> AIOStreams 192.168.100.36:3010 (privé)
```

### AIOStreams (addon Stremio) — déployé le 12 novembre 2026

| Élément | Valeur |
| --- | --- |
| Adresse | <https://aio.skritchz.fr/stremio/configure> (LAN et VPN uniquement) |
| Projet Compose | `/mnt/raid1/docker/aiostreams/compose.yml`, service `aiostreams.service` (activé au démarrage) |
| Image | `ghcr.io/viren070/aiostreams` figée par digest (v2.37.0 au déploiement) |
| Port | `192.168.100.36:3010` → conteneur 3000 ; joignable seulement depuis le LAN et le proxy |
| Données | `/mnt/raid1/docker/aiostreams/data` (base SQLite, caches) |
| Secrets | `/mnt/raid1/docker/aiostreams/.env` (600) : `SECRET_KEY` (ne jamais changer), identifiant `admin` et mot de passe (`AIOSTREAMS_AUTH`) |
| Sécurité | UID 1000, système de fichiers en lecture seule, aucune capacité, authentification obligatoire pour la page de configuration |

Mise à jour : remplacer le digest dans `compose.yml` par celui d'une version
validée, puis `sudo systemctl restart aiostreams`. L'installation et le
rafraîchissement de l'addon dans Stremio exigent l'accès LAN ou VPN. Si le
proxy de flux intégré d'AIOStreams est activé, la lecture passe aussi par
`aio.skritchz.fr` et nécessite donc le LAN/VPN ; sinon les clients lisent
directement les URL externes renvoyées (débrideurs, etc.).

### Réseau

| Élément | Valeur |
| --- | --- |
| Réseau UniFi | `Proxy DMZ`, VLAN 30, `192.168.30.0/24`, passerelle `192.168.30.1`, zone pare-feu **DMZ**, sans DHCP ni IPv6 |
| VM proxy | `proxy`, `192.168.30.10` (statique), Debian 13, 2 vCPU, 1 Gio, disque `/mnt/raid1/vms/proxy.qcow2` (+ `proxy-seed.iso` cloud-init, à conserver), UEFI, démarrage automatique par libvirt |
| NAS | Sous-interface `vlan30` (sur `br0`) et pont `br-dmz`, **sans adresse IP** : `/etc/netplan/60-proxy-dmz.yaml` |
| Câble NAS | Inchangé : LAN natif + VLAN 30 étiqueté sur le même lien |
| Administration | `ssh admin@192.168.30.10` (clé uniquement), autorisé seulement depuis le PC `192.168.100.136` |

### Pare-feu UniFi (politiques par zones, nom « Proxy DMZ isolation »)

| De → Vers | Autorisé | Le reste |
| --- | --- | --- |
| WAN → proxy | TCP 443 uniquement (redirection « HTTPS to Caddy proxy ») | Bloqué ; plus aucune redirection 80 ni UDP |
| DMZ → LAN | HA TCP 8123 ; NAS TCP 2283, 32400, 6880, 6800, 3010 | Bloqué (SSH, SMB, Cockpit, VNC, autres machines) |
| DMZ → Internet | TCP 443, DNS 53, NTP 123, ICMP, réponses | Bloqué (journalisé) |
| DMZ → passerelle | DNS, DHCP, ICMP (règles système) | Administration bloquée |
| LAN → DMZ | TCP 443 vers le proxy, ICMP, SSH depuis le PC d'administration | Bloqué (journalisé) |
| VPN → DMZ / passerelle | TCP 443 vers le proxy ; DNS de la passerelle | LAN, réseau invité et administration bloqués |

Le pare-feu `nftables` de la VM n'accepte en entrée que 443 et le SSH du PC
d'administration ; le routage IP y est désactivé.

### Noms de domaine et certificats

| Nom | Accès | Backend | DNS public (Cloudflare) | DNS local (UniFi) |
| --- | --- | --- | --- | --- |
| `ha.skritchz.fr` | Public | Home Assistant | A → IP WAN (mise à jour par la passerelle) | A → `192.168.30.10` |
| `photos.skritchz.fr` | Public | Immich | A → IP WAN (mise à jour par la passerelle) | A → `192.168.30.10` |
| `downloads.skritchz.fr` | LAN + VPN | AriaNg + `/jsonrpc` | Aucun | A → `192.168.30.10` |
| `plex.skritchz.fr` | LAN + VPN | Plex | Aucun | A → `192.168.30.10` |
| `scritch007.hopto.org` | Public (transition) | Home Assistant | No-IP | — |
| `mangara-photos.hopto.org` | Public (transition) | Immich | No-IP | — |
| `aio.skritchz.fr` | LAN + VPN | AIOStreams `192.168.100.36:3010` | Aucun | A → `192.168.30.10` |

- DNS de `skritchz.fr` hébergé chez **Cloudflare** (nuage gris : aucun proxy
  Cloudflare). Les enregistrements e-mail IONOS (MX, SPF, DMARC) ont été conservés.
- **DNS dynamique** : la passerelle UniFi (Paramètres → Internet / Dynamic DNS,
  service `cloudflare`, utilisateur = `skritchz.fr`) met à jour les enregistrements A
  `ha` et `photos` avec l'IP WAN, en plus des entrées No-IP. Elle utilise un
  jeton Cloudflare dédié, « unifi-ddns » (DNS Edit + Zone Read sur `skritchz.fr`),
  distinct de celui de Caddy. Les noms publics ne dépendent plus d'un domaine
  `hopto.org`, souvent bloqué par les filtres d'entreprise.
- Certificats **Let's Encrypt** obtenus et renouvelés automatiquement par Caddy :
  DNS-01 via l'API Cloudflare pour `*.skritchz.fr`, TLS-ALPN-01 sur le port 443
  pour les noms No-IP. Aucun port 80 nécessaire.
- Le jeton API Cloudflare (droits « Edit DNS » limités à la zone `skritchz.fr`)
  est stocké uniquement dans `/etc/caddy/caddy.env` sur la VM (root:caddy, 640).
- Les noms privés refusent toute connexion dont l'adresse source n'est pas dans
  `192.168.100.0/24` ou `192.168.60.0/24` (VPN), quel que soit l'en-tête
  `X-Forwarded-For`.
- Home Assistant fait confiance au proxy `192.168.30.10/32` (Paramètres →
  Système → Réseau) ; l'entrée `172.30.33.0/24` (Nginx Proxy Manager interne) est conservée.

### Caddy

| Élément | Emplacement |
| --- | --- |
| Binaire | `/usr/local/bin/caddy` — Caddy v2.11.9 + module `caddy-dns/cloudflare` v0.2.4 |
| Configuration | `/etc/caddy/Caddyfile` ; noms No-IP dans `/etc/caddy/legacy-hopto.caddy` |
| Secret | `/etc/caddy/caddy.env` |
| Certificats / compte ACME | `/var/lib/caddy` |
| Journaux | `/var/log/caddy/caddy.log`, `/var/log/caddy/access.log` |
| Service | `caddy.service` (utilisateur `caddy`, systemd durci) |
| Reconstruction du binaire | Sur le NAS : `docker run --rm -v DIR:/out caddy:2.11.9-builder xcaddy build v2.11.9 --with github.com/caddy-dns/cloudflare@v0.2.4 --output /out/caddy` |

```bash
ssh admin@192.168.30.10
sudo systemctl status caddy
sudo caddy validate --config /etc/caddy/Caddyfile   # après modification
sudo systemctl reload caddy
sudo tail -f /var/log/caddy/caddy.log
```

Mises à jour de sécurité Debian automatiques (`unattended-upgrades`).

### Limites connues et points ouverts

- **UPnP reste actif sur le LAN** : Plex crée ses propres redirections
  (ex. 32400) qui contournent le proxy. Choix assumé.
- Une compromission du proxy donne accès aux ports backend autorisés
  ci-dessus et au jeton DNS Cloudflare de la zone.
- Trafic proxy → backends en HTTP sur le réseau interne.
- **WireGuard non encore créé** : les règles VPN existent et le sous-réseau
  prévu est `192.168.60.0/24`. Créer le serveur dans UniFi avec ce sous-réseau.
- Nginx Proxy Manager (module Home Assistant) n'est plus exposé à Internet ;
  il peut être arrêté ou désinstallé une fois la transition confirmée.
- Les noms No-IP sont temporaires : migrer les applications mobiles vers
  `ha.skritchz.fr` et `photos.skritchz.fr`, puis supprimer
  `legacy-hopto.caddy` (ligne `import` dans le Caddyfile). Les noms
  `skritchz.fr` ne dépendent plus de No-IP.
- Redémarrage complet du NAS testé le 12 novembre 2026 : adresse `.36`, VM,
  conteneurs, partages NFS de Home Assistant et sites du proxy reviennent seuls.
- Clé API UniFi « proxy-setup » (expiration 1 mois) à révoquer après usage.
- Sauvegardes de reprise réseau/libvirt du NAS (locales) :
  `/var/backups/nas-proxy-20261111` (root uniquement).

## 3. Organisation du stockage

```text
/mnt/raid1/
|
+-- samba/                         SEUL dossier partagé via Samba
|   +-- telechargements/           destination par défaut d'Aria2
|   +-- ...                        médias et sous-dossiers utilisateur
|
+-- docker/
|   +-- plex/
|   |   +-- compose.yml            définition du conteneur Plex
|   |   +-- config/                configuration et état persistant Plex
|   |   +-- transcode/             fichiers de transcodage
|   |
|   +-- immich/
|   |   +-- compose.yml            définition des quatre services Immich
|   |   +-- data/                  photos et fichiers gérés par Immich
|   |   +-- postgres/              données PostgreSQL
|   |   +-- compose.yml.bak-*      ancien fichier conservé
|   |   +-- start-immich.bat       vestige Windows, non utilisé par systemd
|   |
|   +-- downloads/
|   |   +-- compose.yml            services Aria2 et AriaNg
|   |   +-- config/
|   |   |   +-- aria2.conf         réglages Aria2, dont le secret RPC
|   |   |   +-- aria2.session      file de téléchargements persistante
|   |   +-- connexion.txt          paramètres de connexion et secret RPC
|   |
|   +-- backups/
|   |   +-- immich-20261111-175052/ sauvegarde préalable à la migration
|   |
|   +-- NAS-UTILISATION.txt         aide d'utilisation sur le NAS
|
+-- vms/
|   +-- Home Assistant.vmdk        disque utilisé par la VM
|   +-- Home Assistant.vmx         ancienne définition VMware conservée
|   +-- proxy.qcow2                disque de la VM proxy (DMZ)
|   +-- proxy-seed.iso             données cloud-init de la VM proxy (ne pas supprimer)
|   +-- proxy-src/                 image Debian source et binaire Caddy compilé
|
+-- home-assistant/                exporté en NFSv4 vers la VM HA uniquement
|   +-- frigate/                   enregistrements, clips et exports Frigate (/media/frigate dans HA)
|   +-- backup/                    emplacement de sauvegarde HA « nas_backup » (par défaut)
+-- shared/                        dossier existant, non partagé
+-- lost+found/                    dossier technique ext4
```

Le chemin correct du partage est **`/mnt/raid1/samba`**, et non
`/media/raid1/samba`, qui n'existait pas lors de l'installation.

L'ancien dossier `/mnt/raid1/immich/Immich` a été déplacé vers
`/mnt/raid1/docker/immich`. Le dossier parent vide a ensuite été retiré.

### Correspondance NAS / conteneurs

| Sur le NAS | Dans le conteneur | Accès / usage |
| --- | --- | --- |
| `/mnt/raid1/samba` | Plex : `/media` | Lecture seule |
| `/mnt/raid1/docker/plex/config` | Plex : `/config` | Configuration persistante |
| `/mnt/raid1/docker/plex/transcode` | Plex : `/transcode` | Lecture/écriture |
| `/mnt/raid1/samba` | Aria2 : `/downloads` | Lecture/écriture |
| `/mnt/raid1/docker/downloads/config` | Aria2 : `/config` | Réglages et file persistante |
| `/mnt/raid1/docker/immich/data` | Immich serveur : `/data` | Via volume nommé `immich_server-data` avec liaison au dossier RAID |
| `/mnt/raid1/docker/immich/postgres` | PostgreSQL : `/var/lib/postgresql/data` | Via volume nommé `immich_postgres-data` avec liaison au dossier RAID |
| Volume `immich_model-cache` | Machine-learning : `/cache` | Cache conservé dans le stockage Docker, hors dossier Immich du RAID |

Le cache de modèles est actuellement sous
`/var/lib/docker/volumes/immich_model-cache/_data`.
Les deux autres volumes nommés Immich pointent vers les dossiers du RAID :
leur nom Docker ne signifie pas que les photos et la base ont été déplacées
sur le disque système.

## 4. Emplacement des configurations

| Composant | Fichier ou dossier de référence |
| --- | --- |
| Docker Compose Plex | `/mnt/raid1/docker/plex/compose.yml` |
| Paramètres persistants Plex | `/mnt/raid1/docker/plex/config/Library/Application Support/Plex Media Server/Preferences.xml` |
| État complet Plex, métadonnées et journaux | `/mnt/raid1/docker/plex/config/Library/Application Support/Plex Media Server/` |
| Docker Compose Immich | `/mnt/raid1/docker/immich/compose.yml` |
| Paramètres applicatifs Immich | Répartis entre Compose et la base PostgreSQL ; réglages dans l'administration Immich |
| Docker Compose téléchargements | `/mnt/raid1/docker/downloads/compose.yml` |
| Réglages Aria2 | `/mnt/raid1/docker/downloads/config/aria2.conf` |
| Connexion AriaNg / secret RPC | `/mnt/raid1/docker/downloads/connexion.txt` |
| Réglages de l'interface AriaNg | Stockage local du navigateur ; à renseigner sur un autre navigateur |
| Samba | `/etc/samba/smb.conf` |
| Service Plex | `/etc/systemd/system/plex.service` |
| Service Immich | `/etc/systemd/system/immich.service` |
| Service téléchargements | `/etc/systemd/system/downloads.service` |
| Service VM Home Assistant | `/etc/systemd/system/home-assistant-vm.service` |
| Définition KVM/libvirt Home Assistant | `/etc/libvirt/qemu/home-assistant.xml` |
| Configuration applicative Home Assistant | Dans le système de la VM, donc dans son disque VMDK |
| Exports NFS vers Home Assistant | `/etc/exports.d/home-assistant.exports` (NFSv4 seulement : `/etc/nfs.conf.d/50-v4-only.conf`) |
| Dépendance RAID de libvirt / NFS | `/etc/systemd/system/libvirtd.service.d/raid.conf`, `/etc/systemd/system/nfs-server.service.d/raid.conf` |
| Montage des systèmes de fichiers | `/etc/fstab` |
| Définition RAID mdadm | `/etc/mdadm/mdadm.conf` |
| Réseau / pont LAN du NAS | `/etc/netplan/00-installer-config.yaml` |

La VM est reliée au pont **`br0`**, avec une carte réseau virtuelle `virtio`.
Son disque courant est `/mnt/raid1/vms/Home Assistant.vmdk`.
Le fichier `.vmx` n'est pas la définition utilisée par KVM.

Certains fichiers contiennent des secrets : Compose Immich, configuration
Aria2, `connexion.txt`, préférences et certificats Plex. Ne pas les copier en
clair dans un dossier synchronisé ou public. Aucun de ces contenus n'est
reproduit dans ce document.

## 5. Démarrage et gestion des services

Les services **`plex`**, **`immich`** et **`downloads`** sont activés au démarrage.
Leurs unités systemd :

1. attendent Docker et le réseau ;
2. exigent le montage `/mnt/raid1` ;
3. exécutent Docker Compose en arrière-plan.

Les conteneurs Plex et téléchargements utilisent `restart: unless-stopped`.
Docker attend au démarrage que `192.168.100.36` soit présente sur `br0`
(`/etc/systemd/system/docker.service.d/wait-lan-ip.conf`) : sinon les ports
publiés uniquement sur cette adresse (Aria2, AriaNg, AIOStreams) restent
silencieusement absents.
Immich conserve ses politiques de redémarrage existantes.
Une unité `oneshot` peut être `active (exited)` alors que ses conteneurs tournent :
vérifier également `docker ps`.

La VM Home Assistant démarre via `home-assistant-vm.service`, également activé.
**Attention :** son unité existante utilise `virsh destroy` à l'arrêt, ce qui
équivaut à couper l'alimentation de la VM. Pour un arrêt propre, utiliser
`virsh shutdown home-assistant` et attendre son arrêt.
Contrairement aux trois unités Docker, cette unité ne contient actuellement
pas `RequiresMountsFor=/mnt/raid1`. En revanche, `libvirtd` exige désormais
le montage du RAID (les disques des deux VM y sont).

### Stockage NAS de Home Assistant (depuis le 12 novembre 2026)

Le disque de la VM HA (62 Go) saturait à cause de Frigate. Deux partages NFSv4
du NAS sont montés par le Supervisor (Paramètres → Système → Stockage) :

| Nom dans HA | Usage | Chemin NAS | Vu dans HA |
| --- | --- | --- | --- |
| `frigate` | Média | `/mnt/raid1/home-assistant/frigate` | `/media/frigate` (stockage de Frigate, sans changement de configuration) |
| `nas_backup` | Sauvegarde | `/mnt/raid1/home-assistant/backup` | Emplacement de sauvegarde par défaut |

- Exports limités à `192.168.100.21` ; tous les accès sont convertis en
  `benjamin` (`all_squash`, UID/GID 1000). NFSv3 désactivé.
- Les anciens enregistrements Frigate ont été supprimés ; clips et exports
  ont été copiés sur le NAS (contrôle des tailles) avant suppression.
- Si le NAS ou le RAID est indisponible, Frigate ne peut pas enregistrer.
- Les sauvegardes automatiques HA ne sont **pas programmées**. Les activer dans
  Paramètres → Système → Sauvegardes avec l'emplacement `nas_backup`, sans
  inclure le dossier média (enregistrements Frigate).

```bash
# Connexion
ssh benjamin@192.168.100.36

# Vue d'ensemble
sudo systemctl status plex immich downloads home-assistant-vm smbd --no-pager
docker ps
docker compose ls
sudo virsh list --all

# Redémarrage d'un projet Docker
sudo systemctl restart plex
sudo systemctl restart downloads
sudo systemctl restart immich

# Journaux
sudo journalctl -u plex -u downloads -u immich -n 100 --no-pager
cd /mnt/raid1/docker/immich
docker compose logs --tail 100

# Vérification des ports et de Samba
sudo ss -lntup
sudo testparm -s

# Vérification du RAID
findmnt /mnt/raid1
cat /proc/mdstat
```

Ne pas utiliser `docker compose down -v` ou supprimer les volumes/dossiers
de données pour un simple redémarrage.

Les images Plex, Aria2 et AriaNg ont été figées par digest dans leurs fichiers
Compose pour un déploiement reproductible. Un simple `pull` ne les met donc
pas à une nouvelle version : une mise à jour nécessite de remplacer la
référence par celle d'une version validée. Immich conserve les références
de son installation existante.

## 6. Utilisation des téléchargements et de Plex

### AriaNg / Aria2

1. Ouvrir <http://192.168.100.36:6880>.
2. Si nécessaire, renseigner dans **AriaNg Settings > RPC** :
   HTTP, hôte `192.168.100.36`, port `6800`, chemin `jsonrpc`.
3. Récupérer le secret via SSH dans
   `/mnt/raid1/docker/downloads/connexion.txt`, puis rafraîchir la page.
4. Cliquer **New** et coller une URL, ou plusieurs URLs, **une par ligne**.
5. Dans **Options > Download Path (dir)**, définir le dossier.
6. Cliquer **Download Now**.

| Dossier saisi dans AriaNg | Destination sur le NAS |
| --- | --- |
| `/downloads/telechargements` | `/mnt/raid1/samba/telechargements` |
| `/downloads/Films` | `/mnt/raid1/samba/Films` |
| `/downloads/Musique` | `/mnt/raid1/samba/Musique` |

Les destinations utilisateur doivent être sous `/downloads`.
L'installation vise des **liens directs HTTP/HTTPS**, et non des pages
nécessitant un navigateur, une extraction vidéo ou une connexion interactive.
Les fichiers téléchargés appartiennent à l'UID/GID `1000:1000` de `benjamin`.

### Plex

Ouvrir <http://192.168.100.36:32400/web> et créer les bibliothèques à partir
des chemins visibles dans le conteneur : `/media/Films`, `/media/Musique`, etc.

Plex a accès à `/dev/dri` pour permettre l'accélération matérielle lorsque le
matériel et l'abonnement Plex le permettent. Cela ne prouve pas qu'un
transcodage matériel a effectivement été testé.

À la fin du déploiement initial, Plex répondait mais n'était pas encore
associé à un compte. Si la revendication du serveur nécessite une connexion
locale, depuis Windows :

```powershell
ssh -L 32400:127.0.0.1:32400 benjamin@192.168.100.36
```

Puis ouvrir `http://localhost:32400/web`.

## 7. Partage Samba et sauvegardes existantes

**Seul partage de fichiers :** `\\192.168.100.36\samba`,
correspondant à `/mnt/raid1/samba`.

Les anciens partages `vms`, `home-assistant`, `immich`, `shared` et `raid1`
ont été retirés ; leurs données n'ont pas été supprimées.
Le partage technique `IPC$`, s'il apparaît, n'expose pas un dossier utilisateur.
Le chargement des imprimantes et les partages utilisateurs Samba ont été désactivés.
L'accès invité et les permissions existants du partage `samba` ont été conservés.

### Sauvegarde préalable à la migration Immich

Emplacement :

```text
/mnt/raid1/docker/backups/immich-20261111-175052/
```

Elle contient un export PostgreSQL, l'ancien Compose, l'ancienne unité
systemd et les résultats de contrôle des comptes/photos.
**Ce n'est pas une copie complète des photos**, déplacées sur le même RAID.
Cette sauvegarde reste sur le NAS et ne protège donc pas contre sa perte.

### Sauvegarde de l'ancienne configuration Samba

Emplacement :

```text
/home/benjamin/.local/state/nas-config-backups/samba-20261111-175018/smb.conf
```

Ne pas restaurer ce fichier tel quel sans vérification : il réactiverait les
anciens partages que l'on a explicitement retirés.

## 8. Vérifications effectuées

- Trois projets Docker démarrés depuis les nouveaux dossiers.
- Immich : quatre conteneurs sains, réponse API `pong`.
- Migration Immich : nombre de photos conservé (**4**) et nombre de comptes identique.
- Plex : interface serveur joignable sur TCP 32400.
- Aria2 : requêtes sans secret valide refusées.
- Téléchargement d'une URL puis d'une liste de deux URLs dans un dossier choisi :
  contenu vérifié par SHA-256.
- Fichiers téléchargés conservés après redémarrage de Plex et des téléchargements.
- Interface AriaNg connectée et champ de choix du dossier vérifié.
- Samba : configuration effective ne contenant que `global` et `samba` ;
  anciens accès aux partages fermés.
- Home Assistant : VM en fonctionnement et réponse HTTP 200 sur TCP 8123.
- Unités de démarrage activées ; **aucun redémarrage complet du NAS effectué**.

## 9. Ce qu'il faudrait sauvegarder pour une restauration complète

Ce document est un inventaire, pas une sauvegarde restaurable.
Une vraie sauvegarde devrait inclure :

- les fichiers Compose et unités systemd ;
- les configurations système nécessaires (Samba, réseau, montages et RAID) ;
- les données Plex persistantes ;
- les fichiers Immich et un export cohérent de sa base PostgreSQL ;
- la configuration Aria2 et sa file d'attente, si souhaitée ;
- le contenu du partage Samba ;
- la définition libvirt et une sauvegarde cohérente du disque Home Assistant.

Les secrets doivent être protégés par chiffrement. Pour PostgreSQL et le
disque de la VM, utiliser une procédure cohérente avec l'application plutôt
qu'une simple copie pendant des écritures.
