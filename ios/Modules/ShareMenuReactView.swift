//
//  ShareMenuReactView.swift
//  RNShareMenu
//
//  Created by Gustavo Parreira on 28/07/2020.
//  Modified by Veselin Stoyanov on 03/07/2021.

import Foundation
import MobileCoreServices

@objc(ShareMenuReactView)
public class ShareMenuReactView: NSObject {
    static var viewDelegate: ReactShareViewDelegate?

    @objc
    static public func requiresMainQueueSetup() -> Bool {
        return false
    }

    public static func attachViewDelegate(_ delegate: ReactShareViewDelegate!) {
        guard (ShareMenuReactView.viewDelegate == nil) else { return }

        ShareMenuReactView.viewDelegate = delegate
    }

    public static func detachViewDelegate() {
        ShareMenuReactView.viewDelegate = nil
    }

    @objc(dismissExtension:)
    func dismissExtension(_ error: String?) {
        guard let extensionContext = ShareMenuReactView.viewDelegate?.loadExtensionContext() else {
            print("Error: \(NO_EXTENSION_CONTEXT_ERROR)")
            return
        }

        if error != nil {
            let exception = NSError(
                domain: Bundle.main.bundleIdentifier!,
                code: DISMISS_SHARE_EXTENSION_WITH_ERROR_CODE,
                userInfo: ["error": error!]
            )
            extensionContext.cancelRequest(withError: exception)
            return
        }

        extensionContext.completeRequest(returningItems: [], completionHandler: nil)
        ShareMenuReactView.detachViewDelegate()
    }

    @objc
    func openApp() {
        guard let viewDelegate = ShareMenuReactView.viewDelegate else {
            print("Error: \(NO_DELEGATE_ERROR)")
            return
        }

        viewDelegate.openApp()
        ShareMenuReactView.detachViewDelegate()
    }

    @objc(continueInApp:)
    func continueInApp(_ extraData: [String:Any]?) {
        guard let viewDelegate = ShareMenuReactView.viewDelegate else {
            print("Error: \(NO_DELEGATE_ERROR)")
            return
        }

        let extensionContext = viewDelegate.loadExtensionContext()

        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            print("Error: \(COULD_NOT_FIND_ITEMS_ERROR)")
            return
        }

        viewDelegate.continueInApp(with: items, and: extraData)
        ShareMenuReactView.detachViewDelegate()
    }

    @objc(data:reject:)
    func data(_
            resolve: @escaping RCTPromiseResolveBlock,
            reject: @escaping RCTPromiseRejectBlock) {
        guard let extensionContext = ShareMenuReactView.viewDelegate?.loadExtensionContext() else {
            print("Error: \(NO_EXTENSION_CONTEXT_ERROR)")
            return
        }

        extractDataFromContext(context: extensionContext) { (data, error) in
            guard (error == nil) else {
                reject("error", error?.description, nil)
                return
            }

            resolve([DATA_KEY: data])
        }
    }

    func extractDataFromContext(context: NSExtensionContext, withCallback callback: @escaping ([Any]?, NSException?) -> Void) {
        DispatchQueue.global().async {
            let semaphore = DispatchSemaphore(value: 0)
            let items:[NSExtensionItem]! = context.inputItems as? [NSExtensionItem]
            var results: [[String: String]] = []

            for item in items {
                guard let attachments = item.attachments else {
                    callback(nil, NSException(name: NSExceptionName(rawValue: "Error"), reason:"couldn't find attachments", userInfo:nil))
                    return
                }

                for provider in attachments {
                    if provider.hasItemConformingToTypeIdentifier(kUTTypeURL as String) {
                        provider.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil) { (item, error) in
                            let url: URL! = item as? URL

                            results.append([DATA_KEY: url.absoluteString, MIME_TYPE_KEY: "text/plain"])

                            semaphore.signal()
                        }
                        semaphore.wait()
                    } else if provider.hasItemConformingToTypeIdentifier(kUTTypeText as String) {
                        provider.loadItem(forTypeIdentifier: kUTTypeText as String, options: nil) { (item, error) in
                            let text:String! = item as? String

                            results.append([DATA_KEY: text, MIME_TYPE_KEY: "text/plain"])

                            semaphore.signal()
                        }
                        semaphore.wait()
                    } else if provider.hasItemConformingToTypeIdentifier(kUTTypeImage as String) {
                        provider.loadItem(forTypeIdentifier: kUTTypeImage as String, options: nil) { (item, error) in
                            let url: URL! = self.getFileUrl(from: item as Any, withCallback: callback) as? URL

                            results.append([DATA_KEY: url.absoluteString, MIME_TYPE_KEY: self.extractMimeType(from: url)])

                            semaphore.signal()
                        }
                        semaphore.wait()
                    } else if provider.hasItemConformingToTypeIdentifier(kUTTypeData as String) {
                        provider.loadItem(forTypeIdentifier: kUTTypeData as String, options: nil) { (item, error) in
                            let url: URL! = self.getFileUrl(from: item as Any, withCallback: callback) as? URL

                            results.append([DATA_KEY: url.absoluteString, MIME_TYPE_KEY: self.extractMimeType(from: url)])

                            semaphore.signal()
                        }
                        semaphore.wait()
                    } else {
                        callback(nil, NSException(name: NSExceptionName(rawValue: "Error"), reason:"couldn't find provider", userInfo:nil))
                    }
                }
            }

            callback(results, nil)
        }
    }

    func getFileUrl(from data: Any, withCallback callback: @escaping ([Any]?, NSException?) -> Void) -> Any {
        var url: URL! = nil
        var image: UIImage! = nil
        
        if data is UIImage {
            image = data as? UIImage
        }

        if data is Data {
            image = UIImage(data: data as! Data)!
        }
        
        if (image != nil) {
            let imageData: Data! = image.pngData()

            // Creating temporary URL for image data (UIImage)
            guard let imageURL = NSURL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("TemporaryImage.png") else {
                callback(nil, NSException(name: NSExceptionName(rawValue: "Error"), reason:"Can't save image in temp file", userInfo:nil))
                return ""
            }
            
            do {
                // Writing the image to the URL
                try imageData.write(to: imageURL)
                url = imageURL
            } catch {
                callback(nil, NSException(name: NSExceptionName(rawValue: "Error"), reason:"Can't write image to URL", userInfo:nil))
            }
        } else {
            guard let toUrl = data as? URL else {
                callback(nil, NSException(name: NSExceptionName(rawValue: "Error"), reason:"Can't turn data into URL", userInfo:nil))
                return ""
            }

            url = toUrl;
        }

        return url!
    }

    func extractMimeType(from url: URL) -> String {
      let fileExtension: CFString = url.pathExtension as CFString
      guard let extUTI = UTTypeCreatePreferredIdentifierForTag(
              kUTTagClassFilenameExtension,
              fileExtension,
              nil
      )?.takeUnretainedValue() else { return "" }

      guard let mimeUTI = UTTypeCopyPreferredTagWithClass(extUTI, kUTTagClassMIMEType)
      else { return "" }

      return mimeUTI.takeUnretainedValue() as String
    }
}
