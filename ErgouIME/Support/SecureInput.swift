// ergou-ime — secure input (password fields) detection.
// SPDX-License-Identifier: GPL-3.0-only
//
// Privacy rule 6: while secure input is on we do not record, do not write the
// clipboard, do not show candidates and do not learn. Whether
// IsSecureEventInputEnabled() is reliable inside an input method process is
// verified in M4 (T4.2).

import Carbon

enum SecureInput {
    static var isActive: Bool { IsSecureEventInputEnabled() }
}
