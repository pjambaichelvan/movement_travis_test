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

class UploadManager: NSObject {
  //static let hostURL = URL(string: "http://Seans-MacBook-Pro.local.:9000/data")! // Point to server end point for POST
  static let hostURL = URL(string: "http://192.168.50.23:9000/data")! // Point to server end point for POST
  //static let hostURL = URL(string: "http://162.253.55.137:80/data")! // Point to server end point for POST
  
  // Configuration paramaters
  static let uploadFileSizeThreashold = UInt64(0) // Will trigger an upload right away
  static let uploadTimeout = TimeInterval(5.0*60.0)  // Time to allow upload tasks to complete before returning error
  static let df : DateFormatter =  {
    let df = DateFormatter()
    df.locale = Locale(identifier: "en_US_POSIX")
    df.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
    return df
  }()
    
    var className: String {
        return String(describing: type(of: self))
    }
    
  static let sharedInstance = UploadManager()
  
  var queue = DispatchQueue(label: "ca.unitcircle.uploadmanager.queue", qos: .background)
  var _uploadTask: URLSessionUploadTask?
  var _uploadTaskValid = false
  var uploadTask: URLSessionUploadTask? {
    get {
      return _uploadTaskValid ? _uploadTask : nil
    }
    set (task) {
      // Setting uploadTask should be inside a queue.sync {...} block
      self._uploadTask = task
      self._uploadTaskValid = true
    }
  }
  var appSupportURL: URL
  var queueURL: URL
  var uploadURL: URL

  var bgSession: URLSession?
  
  private override init() {
    appSupportURL = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
    
    if !FileManager.default.fileExists(atPath: appSupportURL.path) {
      do {
        try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true, attributes: nil)
      }
      catch {
        uc_os_log("init: unable to create Application Support directory error: %{public}@", "\(error.localizedDescription)")
      }
    }
    
    queueURL  = appSupportURL.appendingPathComponent("queue.data")
    uploadURL = appSupportURL.appendingPathComponent("upload.data")
    super.init()
    
    let configuration = URLSessionConfiguration.background(withIdentifier: "bgSessionConfiguration")
    configuration.allowsCellularAccess = true
    configuration.urlCache = nil // Disable chaching of any responses
    configuration.sessionSendsLaunchEvents = true
    configuration.isDiscretionary = true
    // Time that server must respond in after request has been sent, otherwise connection closed
    configuration.timeoutIntervalForRequest = 60.0  // default 60 seconds
    // Time that iOS will continue to retry server - if expires then original request returns Timedout error.
    configuration.timeoutIntervalForResource = 15.0*60.0  // 15 minutes - default 7 days
    bgSession = URLSession(configuration: configuration, delegate: self, delegateQueue: OperationQueue())
    // OperationQueue() qos defaults to backgound

    uc_os_log("UploadManager.init - task list")
    bgSession?.getAllTasks(completionHandler: { tasks in
      uc_os_log("UploadManager.init - pending tasks %{public}@", "\(tasks.count)")
      self.queue.sync {
        if tasks.count > 0 {
          for task in tasks {
            uc_os_log("UploadManager.init task: %{public}@", "\(task.debugDescription) \(task.state.rawValue)")
          }
          let uploadTask = tasks[0] as? URLSessionUploadTask
          if uploadTask == nil {
            uc_os_log("UploadManager.init unable to downcast task to URLSessionUploadTask")
          }
          else if uploadTask!.state == .running {
             self.uploadTask = uploadTask
          }
          else {
            if uploadTask!.state == .suspended {
              uc_os_log("UploadManager.init cancelling suspended task")
              uploadTask!.cancel()
            }
             self.uploadTask = nil
          }
        }
        else {
          self.uploadTask = nil
        }
      }
    })
  }
  
  func schedulePayload(_ item: String) {
    queue.sync {
      uc_os_log("schedulePayload: %{public}@", item)
      if let fileHandle = FileHandle(forWritingAtPath: queueURL.path) {
        uc_os_log("schedulePayload: appending to file")
        defer {
          fileHandle.closeFile()
        }
        fileHandle.seekToEndOfFile()
        
        let payload = ",\"\(item)\"".data(using: .utf8)!
        fileHandle.write(payload)
      }
      else {
        uc_os_log("schedulePayload: creating file")
        do {
          let payload = "{ \"data\": [ \"\(item)\"".data(using: .utf8)!
          try payload.write(to: queueURL, options: .atomic)
        }
        catch {
          uc_os_log("schedulePayload: creating file failed: %{public}@", queueURL.path)
        }
      }
    }
  }
  
  func checkUpload() {
    var doUpload =  false;
    queue.sync {
      do {
        let attr = try FileManager.default.attributesOfItem(atPath: queueURL.path)
        let fileSize = attr[.size] as! UInt64
        uc_os_log("schedulePayload: new file size: %{public}@", "\(fileSize)")
        
        if (fileSize > UploadManager.uploadFileSizeThreashold) {
          doUpload = true;
        }
      }
      catch {
        uc_os_log("schedulePayload: unable to get file size %{public}@", "\(error.localizedDescription)")
      }
    }
    if doUpload {
      uploadPayload()
    }
  }
  
  private func commitPayload() {
    // Callers must only call this funcstion inside a queue.sync {...} block
    if !FileManager.default.fileExists(atPath: uploadURL.path) && FileManager.default.fileExists(atPath: queueURL.path){
      uc_os_log("commitPayload: upload not pending and new data available")
      if let fileHandle = FileHandle(forWritingAtPath: queueURL.path) {
        defer {
          fileHandle.closeFile()
        }
        fileHandle.seekToEndOfFile()
        
        let payload = "], \"time\": \"\(UploadManager.df.string(from: Date()))\"}".data(using: .utf8)!
        fileHandle.write(payload)
      }
      
      // Previous upload completed (or is first time) and we have new data to send
      do {
        try FileManager.default.moveItem(at: queueURL, to: uploadURL)
      }
      catch {
        uc_os_log("commitPayload: unable to move: %{public}@", "\(queueURL) to: \(uploadURL) error: \(error.localizedDescription)")
        return
      }
    }
  }
  
  func uploadPayload() {
    queue.sync {
      if uploadTask == nil {
        self.commitPayload()
        
        if FileManager.default.fileExists(atPath: uploadURL.path) {
          // We have data to send - either new or from a previous attempt that didn't compelete because app was terminated
          // Server will need to handle possible duplicate upload
          var req = URLRequest(url: UploadManager.hostURL)
          req.httpMethod = "POST"
          uploadTask = bgSession?.uploadTask(with: req, fromFile: uploadURL)
          uploadTask?.resume()
          uc_os_log("uploadPayload: upload task started %{public}@", "\(String(describing: uploadTask))");
        }
        else {
          uc_os_log("uploadPayload: no data to upload")
        }
      }
      else {
        uc_os_log("uploadPayload: upload not scheduled: uploadTask %{public}@", _uploadTaskValid ? "aready running" : "not valid yet")
      }
    }
  }
}

extension UploadManager: URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    var uploadAgain = false
    if error == nil {
      if let resp = task.response as? HTTPURLResponse {
        uc_os_log("urlSession:task:didCompleteWithError: %{public}@", "\(resp.statusCode) - \(resp.allHeaderFields)")
        if (resp.statusCode == 200) {
          do {
            if FileManager.default.fileExists(atPath: uploadURL.path) {
              uc_os_log("urlSession:task:didCompleteWithError - removing upload file")
              try FileManager.default.removeItem(at: uploadURL)
              uploadAgain = true
            }
            else {
              uc_os_log("urlSession:task:didCompleteWithError - upload file no longer exists")
            }
          }
          catch {
            uc_os_log("urlSession:task:didCompleteWithError - unable to remove upload file")
          }
        }
        else {
          uc_os_log("urlSession:task:didCompleteWithError - unhandled status code")
        }
      }
      else if task.response == nil {
        uc_os_log("urlSession:task:didCompleteWithError - task response was not a HTTPURLResponse - nil")
      }
      else {
        uc_os_log("urlSession:task:didCompleteWithError - task response was not a HTTPURLResponse %{public}@", task.response!)
      }
    }
    else {
      let error = error! as NSError
      if error.domain == NSURLErrorDomain {
        switch error.code {
        case NSURLErrorTimedOut:
          uc_os_log("urlSession:task:didCompleteWithError: NSURLErrorTimedOut")
          uploadAgain = true // Let iOS run through it's retry timers again
        case NSURLErrorCancelled:
          uc_os_log("urlSession:task:didCompleteWithError: NSURLErrorCancelled")
        default:
          uc_os_log("urlSession:task:didCompleteWithError: %{public}@", "\(error.debugDescription)")
        }
      }
      else {
        uc_os_log("urlSession:task:didCompleteWithError: %{public}@", "\(error.debugDescription)")
      }
    }
    
    queue.sync {
      uploadTask = nil
    }
    if uploadAgain {
      uploadPayload()
    }
  }
  
  func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
    uc_os_log("urlSession:task:didSendBodyData: %{public}@", "\(bytesSent) - \(totalBytesSent) - \(totalBytesExpectedToSend)")
  }
}

extension UploadManager: URLSessionDataDelegate {
  //  This delegate function is not used in background uploads
  //  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
  //    if let resp = didReceive as? HTTPURLResponse {
  //      print("didReceive \(resp.statusCode) \(resp.allHeaderFields)")
  //    }
  //    else {
  //      print("Unable to cast response to HTTPURLResponse")
  //    }
  //    uploadTask = nil
  //    DispatchQueue.main.async {
  //      completionHandler(.allow)
  //    }
  //  }
  
  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    // Seems like there is a bug in OS stack where sometimes if it is a BG session
    // the stack will call with data == nil before
    // URLSessionDelegate.urlSessionDidFinishEvents(forBackgroundURLSession: URLSession) is called.
    // The second call has the data.
    // Doesn't seem to happen every time.
    // Recommendation is to use enumerate API to extract data versus
    // Using String(data:, encoding:) which makes a copy to flatten to contiguous memory
    //      data!.enumerateBytes { bytes,range,stop in
    //        print("enumerate \(bytes) \(range)")
    //      }
    uc_os_log("urlSession:dataTask:didReceive: %{public}@", data.encodeHex())
  }
}

extension UploadManager: URLSessionDelegate {
  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    uc_os_log("urlSessionDidFinishEvents:forBackgroundURLSession: %{public}@", "\(session.configuration.identifier!)")
  }
  func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
    uc_os_log("urlSession:didBecomeInvalidWithError: %{public}@", "\(session) - \(error.debugDescription)")
  }
}
