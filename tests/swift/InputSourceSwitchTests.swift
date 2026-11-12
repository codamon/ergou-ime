// ergou-ime — switching the input source to 二狗 starts in Chinese.
// SPDX-License-Identifier: GPL-3.0-only

let inputSourceSwitchTests: [Test] = [
    ("switch: from another source to ours wants Chinese", {
        var s = InputSourceSwitch(oursSelected: true)
        check(!s.changed(toOurs: false, secureInput: false), "leaving asks for nothing")
        check(s.changed(toOurs: true, secureInput: false), "coming back wants Chinese")
    }),
    ("switch: started on another source", {
        var s = InputSourceSwitch(oursSelected: false)
        check(s.changed(toOurs: true, secureInput: false), "first switch to ours wants Chinese")
    }),
    ("switch: a password field's own switch does not count", {
        var s = InputSourceSwitch(oursSelected: true)
        check(!s.changed(toOurs: false, secureInput: true), "macOS switched away for the password")
        check(!s.changed(toOurs: true, secureInput: false), "and back: English stays (terminal after sudo)")
        check(!s.changed(toOurs: false, secureInput: false), "the user leaves")
        check(s.changed(toOurs: true, secureInput: false), "the user comes back: Chinese")
    }),
    ("switch: between two other sources, or ours to ours", {
        var s = InputSourceSwitch(oursSelected: false)
        check(!s.changed(toOurs: false, secureInput: false), "ABC to another layout")
        var t = InputSourceSwitch(oursSelected: true)
        check(!t.changed(toOurs: true, secureInput: false), "one of our modes to the other")
    }),
]
