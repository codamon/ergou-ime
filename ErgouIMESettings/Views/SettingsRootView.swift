// ErgouIME Settings — root view.
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

struct SettingsRootView: View {
    @EnvironmentObject private var router: PageRouter

    var body: some View {
        TabView(selection: $router.page) {
            GeneralSettingsView()
                .tabItem { Label(SettingsPage.general.title, systemImage: SettingsPage.general.symbol) }
                .tag(SettingsPage.general)
            PhrasesView()
                .tabItem { Label(SettingsPage.phrases.title, systemImage: SettingsPage.phrases.symbol) }
                .tag(SettingsPage.phrases)
            ModelSettingsView()
                .tabItem { Label(SettingsPage.models.title, systemImage: SettingsPage.models.symbol) }
                .tag(SettingsPage.models)
            TermsView()
                .tabItem { Label(SettingsPage.terms.title, systemImage: SettingsPage.terms.symbol) }
                .tag(SettingsPage.terms)
            AboutView()
                .tabItem { Label(SettingsPage.about.title, systemImage: SettingsPage.about.symbol) }
                .tag(SettingsPage.about)
        }
        .padding()
    }
}
