// Developer: Sebastian Santos
// Attribution ID: PUSH-DEV-SEBASTIAN-SANTOS
// Scheduler regression checks. No app, Keychain, installer, or management action is run.
import Foundation

var count = 0
func check(_ condition: @autoclosure () -> Bool, _ label: String) {
    guard condition() else { fatalError("FAIL: " + label) }
    count += 1
}
let now = Date(timeIntervalSince1970: 1_800_000_000)
let past = now.addingTimeInterval(-86400)
let future = now.addingTimeInterval(7 * 86400)
for deadline in [past, now, future] {
    let range = reminderPickerRange(now: now, deadline: deadline)
    check(range.lowerBound == now, "picker lower bound")
    check(range.upperBound >= range.lowerBound, "expired deadline never constructs inverted range")
    check(range.upperBound == max(now, deadline), "range preserves future deadline")
}
check(reminderTestDeadline(configured: past, manualTest: false, now: now) == past, "production retains expired policy")
check(reminderTestDeadline(configured: past, manualTest: true, now: now) == future, "manual expired policy gets sample window")
check(reminderTestDeadline(configured: future, manualTest: true, now: now) == future, "future policy preserved in preview")
check(reminderTestDeadline(configured: nil, manualTest: true, now: now) == future, "missing policy gets default window")
check(!validReminderDate(past, deadline: future, now: now), "past selection rejected")
check(!validReminderDate(now, deadline: future, now: now), "present selection rejected")
check(validReminderDate(now.addingTimeInterval(3600), deadline: future, now: now), "future selection accepted")
check(validReminderDate(future, deadline: future, now: now), "until deadline accepted")
check(!validReminderDate(future.addingTimeInterval(1), deadline: future, now: now), "after deadline rejected")
check(!validReminderDate(now.addingTimeInterval(1), deadline: past, now: now), "expired policy cannot schedule later")
for state in ["softNudge", "hardBlock", "compliant", "error", "rebootNudge"] {
    check(!popupResultMessage(state: state, exitCode: 5).contains("Toast"), "non-toast cannot report toast timeout")
    let crash = popupProcessResult(status: 5, reason: .uncaughtSignal)
    check(crash == -5, "SIGTRAP cannot masquerade as response 5")
    check(popupResultMessage(state: state, exitCode: crash).contains("crashed"), "crash reported explicitly")
    check(!toastRequestedInstall(exitCode: crash), "crash never requests installation")
}
check(popupProcessResult(status: 133, reason: .exit) == -5, "wrapped SIGTRAP detected")
for response: Int32 in [0, 1, 2, 3, 4, 5, 6, 99, 100, 101] {
    check(popupProcessResult(status: response, reason: .exit) == response, "normal responses preserved")
    check(toastRequestedInstall(exitCode: response) == (response == 0), "only explicit install response installs")
}
check(popupResultMessage(state: "toast", exitCode: 5) == "Toast auto-dismissed", "real toast timeout retained")
check(popupResultMessage(state: "softNudge", exitCode: 3) == "User scheduled a reminder", "schedule result retained")
check(popupResultMessage(state: "softNudge", exitCode: 1) == "User chose Later", "Later distinct")
check(popupResultMessage(state: "softNudge", exitCode: 2) == "User dismissed", "close distinct")
print("Passed \(count) scheduler and response regression checks. No PUSH app or upgrade was launched.")
