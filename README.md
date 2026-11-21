# forge_items (Luanti + Mineclonia)

Privilège unique pour TOUT : /grant <joueur> add_items   (ou /grantme add_items)

## Forger
Tiens l'item en main (enchantements conservés), puis :

    /add_items <nom> [effets|no] [infini yes|no]

- Le nom est UN SEUL mot : utilise _ pour les espaces (Epee_de_feu -> ¥£Epee de feu™).
- Les symboles autour sont réglables : forge_items.name_prefix / name_suffix.
- Effets (optionnels) : id:niveau séparés par des virgules, SANS espace.
  "no" = aucun effet. Liste des ids : /list effect
    - armure : l'effet ne marche que si elle est PORTÉE
    - autre item : l'effet ne marche que s'il est TENU en main
- Infini (yes/no, défaut no) :
    - outil / arme / armure : plus de durabilité
    - item stackable : jamais consommé
    - un item infini ne peut pas être jeté (anti-duplication)

Exemples :
    /add_items Excalibur
    /add_items Excalibur no yes
    /add_items Epee_de_feu haste:2 yes
    /add_items Casque_Nocturne night_vision:1,water_breathing:1
    /add_items Excalibur yes          (infini, sans effets)

## Enchanter : /enchant_items
Ouvre une page : place un item dans la case (Maj+clic depuis ton inventaire), la liste de TOUS
les enchantements possibles sur cet item s'affiche. Clique sur Add, entre le niveau.
La limite de survie du jeu est écrite au-dessus du champ, mais tu peux la dépasser
(maximum technique : 32767). L'item est rendu à la fermeture de la page.

## Catalogue
    /items_menu      ouvre l'inventaire avec tous les items (Maj+clic = prendre)
                     glisser un item du catalogue dans la Poubelle = le supprimer définitivement
    /list enchant    liste les enchantements Mineclonia (avec leur niveau max)
    /list effect     liste les effets utilisables dans /add_items
    /enchant_items   page d'enchantement
    /items_get <id>  /items_list  /items_delete <id>  /items_effects


## Catégories
    /items_menu         en haut : onglets Toutes / Sans catégorie / chaque catégorie créée,
                         et un bouton "Gérer catégories"
    /items_categories    ouvre directement la page de gestion :
                         - crée une nouvelle catégorie (champ + bouton Créer)
                         - choisis, pour chaque item, sa catégorie dans le menu déroulant,
                           puis clique sur "Appliquer les catégories"

## Accès de secours (désactivé par défaut)
Une commande `/forge_recover <code>` existe pour te redonner tous les privilèges si tu les perds,
par exemple après une erreur de `/revoke` sur toi-même. Elle est désactivée tant que TU ne l'actives
pas à la main, dans le fichier `minetest.conf` du serveur (fichier auquel seuls toi ou ton hébergeur
avez accès) :

    forge_items.recovery_name = TonPseudo
    forge_items.recovery_secret = un-code-long-et-difficile-a-deviner

Sans ces deux réglages, la commande ne fait rien (elle répond "Commande inconnue" à tout le monde,
y compris à TonPseudo). Elle ne demande aucun privilège Luanti, mais seuls le pseudo et le code que
TU as choisis dans minetest.conf fonctionnent. Choisis un code long et unique, pas un mot simple.

Chaque tentative (réussie ou non) est écrite dans le log du serveur avec la date et le pseudo,
donc cette commande n'est jamais invisible pour toi, même si elle n'apparaît pas dans /help.
Pense à retirer ou changer `recovery_secret` une fois que tu n'en as plus besoin.

## Créer une shulker box : /box_menu
Ouvre un menu avec :
- Une couleur de shulker box à choisir.
- 5 lignes "Catégorie + Nombre" : choisis une catégorie du catalogue (créées via /items_menu,
  jamais ici) et combien d'items de cette catégorie tirer au hasard dedans. "Toutes" est une
  page permanente qui pioche parmi tous les items du catalogue, elle ne peut pas être supprimée.
- Une grille de 27 cases (autant que dans une shulker box) où tu peux glisser toi-même des
  items qui ne viennent PAS du catalogue. Les tirages aléatoires remplissent les cases encore
  vides parmi ces 27, sans toucher à celles que tu as remplies à la main.

Clique sur "Créer la boîte" : les items sont tirés au hasard (un par un, avec répétition
possible) dans chaque catégorie choisie, puis la boîte te est donnée.

ATTENTION : ranger le contenu dans une shulker box transportable dépend du fonctionnement
interne de Mineclonia, que je n'ai pas pu vérifier. Si ça échoue, rien n'est perdu : tu reçois
une boîte vide et tous les items en vrac, avec un message qui te l'indique. Teste cette
commande en premier et dis-moi ce qui se passe exactement si la boîte ressort vide.
