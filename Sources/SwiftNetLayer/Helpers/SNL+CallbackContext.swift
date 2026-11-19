import Dispatch
import Foundation

public enum SNLCallbackContext: Sendable {
    case waitUnsupported
    case unchecked // Allows synchronous waiting without checking the callback queue.
    case dispatchQueue(DispatchQueue)
    case operationQueue(OperationQueue)
}
