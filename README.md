# SleepWithMe

Minuteur de sommeil pour la barre de menus de macOS 26. Pas besoin de Xcode :
les outils en ligne de commande suffisent.

## Compiler et lancer

Dans le Terminal, depuis ce dossier :

    ./build.sh

Une lune apparaît dans la barre de menus. Quand tout te convient :

    ./build.sh install

copie l'appli dans /Applications (utile pour l'option « Lancer à l'ouverture de session »).

## Autorisation d'accessibilité

Elle sert à mettre la lecture en pause à la fin du minuteur. L'appli étant signée
localement, macOS la redemande après chaque recompilation : dans Réglages Système >
Confidentialité et sécurité > Accessibilité, retire l'ancienne entrée SleepWithMe
puis accepte de nouveau.

## Réglages faciles à modifier

Dans `SleepWithMe/SleepTimer.swift` : `maxMinutes` (180) et `fadeDuration` (45 secondes).
Dans `SleepWithMe/PanelView.swift` : les couleurs (`Theme`) et les préréglages (15, 30, 45, 60).
