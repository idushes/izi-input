import Cocoa

// Отключаем буферизацию вывода для мгновенного логирования
setbuf(__stdoutp, nil)

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate

// Runs the main event loop
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
