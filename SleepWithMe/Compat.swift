import SwiftUI

/// Le SDK macOS 26 déclare aussi `@State` sous forme de macro, dont le module d'extension
/// n'est livré qu'avec Xcode. Cet alias pointe directement vers le type `State` classique,
/// ce qui permet de compiler avec les seuls outils en ligne de commande.
typealias LocalState<Value> = SwiftUI.State<Value>
