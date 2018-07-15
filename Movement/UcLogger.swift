// Copyright 2017 Unit Circle Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import os.log

func synchronized<L: NSLocking>(lockable: L, criticalSection: () -> ()) {
  lockable.lock()
  criticalSection()
  lockable.unlock()
}

let lock = NSLock()
let logFile: URL = {
  let documentDir =  try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
  return documentDir.appendingPathComponent("debug.log")
}()

func log_to_file(_ text: String) {
  synchronized(lockable: lock, criticalSection: {
    if let file = FileHandle(forWritingAtPath: logFile.path) {
      defer {
        file.closeFile()
      }
      file.seekToEndOfFile()
      file.write(text.data(using: .utf8)!)
    }
    else {
      do {
        let payload = text.data(using: .utf8)!
        try payload.write(to: logFile, options: .atomic)
      }
      catch {
        os_log("creating file failed: %{public}@)", logFile.path)
      }
    }
  })
}

let df : DateFormatter =  {
  let df = DateFormatter()
  df.locale = Locale(identifier: "en_US_POSIX")
  df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
  return df
}()

// Ensure all logging ends up in a local file that allows us to extract later if needed.
// See https://stackoverflow.com/questions/9097424/logging-data-on-device-and-retrieving-the-log
// Also in the .plist file make sure that "Application supports iTunes file sharing exists" and is set to YES so that you can access through iTunes
// Using reopsn on stderr with os_log does not seem to work.  Once disconnected from Console loggin is not sent anywhere, i..e this does not work.
//    let logFile = documentDir.appendingPathComponent("\(Date()).log")
//    freopen(logFile.path, "a+", stderr)
// Instead we duplicate the log to a file in Documents dir.
// TODO This could use some cleanup/beter naming
// TODO Might be handy to print [pid:threadid]
// TODO More calling options
func uc_os_log(_ text: StaticString, _ value: CVarArg) {
  os_log(text, value)
  log_to_file(String(format: "[\(df.string(from: Date()))] " + String(describing: text).replacingOccurrences(of: "%{public}@", with: "%@"), value) + "\n")
}

func uc_os_log(_ text: StaticString) {
  os_log(text)
  log_to_file(String(format: "[\(df.string(from: Date()))] " + String(describing: text).replacingOccurrences(of: "%{public}@", with: "%@")) + "\n")
}
