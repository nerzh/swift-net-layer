//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 27.01.2020.
//

import Foundation

public enum SNLMIMEType: Hashable, Sendable, CustomStringConvertible {

    // APPLICATION
    case applicationAtom
    case applicationEDIX12
    case applicationEDIFACT
    case applicationJson
    case applicationProblemJson
    case applicationJsonLD
    case applicationJavascript
    case applicationOctetStream
    case applicationOgg
    case applicationPDF
    case applicationPostScript
    case applicationSOAP
    case applicationFontWoff
    case applicationxXHTML
    case applicationDTD
    case applicationXOP
    case applicationZIP
    case applicationGzip
    case applicationZstd
    case applicationWASM
    case applicationBitTorrent
    case applicationTeX
    case applicationXML
    case applicationYAML
    case applicationCBOR
    case applicationDOC
    case applicationDOCX
    case applicationXLS
    case applicationXLSX
    case applicationPPT
    case applicationPPTX

    // X
    case applicationXFormEncodedData
    case applicationXDVI
    case applicationXLaTeX
    case applicationXTrueType
    case applicationXAdobeFlash
    case applicationXStuffIt
    case applicationXRAR
    case applicationXTarball
    case applicationXJQuery
    case applicationXJavascript

    // IMAGE
    case imageGIF
    case imageJPEG
    case imagePJPEG
    case imagePNG
    case imageAPNG
    case imageSVG
    case imageTIFF
    case imageICO
    case imageWBMP
    case imageWebP
    case imageAVIF
    case imageHEIC
    case imageHEIF
    case imageBMP

    // AUDIO
    case audioMP3
    case audioM4A
    case audioOgg
    case audioFLAC

    // VIDEO
    case videoMP4
    case videoMPEG
    case videoQuickTime
    case videoOgg

    // FONT
    case fontWoff
    case fontWoff2
    case fontTTF
    case fontOTF

    // MULTIPART
    case multipartMixed
    case multipartAlternative
    case multipartRelated
    case multipartFormData
    case multipartSigned
    case multipartEncrypted

    // TEXT
    case textCMD
    case textCSS
    case textCSV
    case textHTML
    case textJavaScript
    case textPlain
    case textPHP
    case textXML
    case textMarkdown
    case textCacheManifest

    case custom(String)

    public var rawValue: String {
        switch self {
        case .applicationAtom: return "application/atom+xml"
        case .applicationEDIX12: return "application/EDI-X12"
        case .applicationEDIFACT: return "application/EDIFACT"
        case .applicationJson: return "application/json"
        case .applicationProblemJson: return "application/problem+json"
        case .applicationJsonLD: return "application/ld+json"
        case .applicationJavascript: return "application/javascript"
        case .applicationOctetStream: return "application/octet-stream"
        case .applicationOgg: return "application/ogg"
        case .applicationPDF: return "application/pdf"
        case .applicationPostScript: return "application/postscript"
        case .applicationSOAP: return "application/soap+xml"
        case .applicationFontWoff: return "application/font-woff"
        case .applicationxXHTML: return "application/xhtml+xml"
        case .applicationDTD: return "application/xml-dtd"
        case .applicationXOP: return "application/xop+xml"
        case .applicationZIP: return "application/zip"
        case .applicationGzip: return "application/gzip"
        case .applicationZstd: return "application/zstd"
        case .applicationWASM: return "application/wasm"
        case .applicationBitTorrent: return "application/x-bittorrent"
        case .applicationTeX: return "application/x-tex"
        case .applicationXML: return "application/xml"
        case .applicationYAML: return "application/yaml"
        case .applicationCBOR: return "application/cbor"
        case .applicationDOC: return "application/msword"
        case .applicationDOCX: return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case .applicationXLS: return "application/vnd.ms-excel"
        case .applicationXLSX: return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case .applicationPPT: return "application/vnd.ms-powerpoint"
        case .applicationPPTX: return "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case .applicationXFormEncodedData: return "application/x-www-form-urlencoded"
        case .applicationXDVI: return "application/x-dvi"
        case .applicationXLaTeX: return "application/x-latex"
        case .applicationXTrueType: return "application/x-font-ttf"
        case .applicationXAdobeFlash: return "application/x-shockwave-flash"
        case .applicationXStuffIt: return "application/x-stuffit"
        case .applicationXRAR: return "application/x-rar-compressed"
        case .applicationXTarball: return "application/x-tar"
        case .applicationXJQuery: return "text/x-jquery-tmpl"
        case .applicationXJavascript: return "application/x-javascript"
        case .imageGIF: return "image/gif"
        case .imageJPEG: return "image/jpeg"
        case .imagePJPEG: return "image/pjpeg"
        case .imagePNG: return "image/png"
        case .imageAPNG: return "image/apng"
        case .imageSVG: return "image/svg+xml"
        case .imageTIFF: return "image/tiff"
        case .imageICO: return "image/vnd.microsoft.icon"
        case .imageWBMP: return "image/vnd.wap.wbmp"
        case .imageWebP: return "image/webp"
        case .imageAVIF: return "image/avif"
        case .imageHEIC: return "image/heic"
        case .imageHEIF: return "image/heif"
        case .imageBMP: return "image/bmp"
        case .audioMP3: return "audio/mpeg"
        case .audioM4A: return "audio/mp4"
        case .audioOgg: return "audio/ogg"
        case .audioFLAC: return "audio/flac"
        case .videoMP4: return "video/mp4"
        case .videoMPEG: return "video/mpeg"
        case .videoQuickTime: return "video/quicktime"
        case .videoOgg: return "video/ogg"
        case .fontWoff: return "font/woff"
        case .fontWoff2: return "font/woff2"
        case .fontTTF: return "font/ttf"
        case .fontOTF: return "font/otf"
        case .multipartMixed: return "multipart/mixed"
        case .multipartAlternative: return "multipart/alternative"
        case .multipartRelated: return "multipart/related"
        case .multipartFormData: return "multipart/form-data"
        case .multipartSigned: return "multipart/signed"
        case .multipartEncrypted: return "multipart/encrypted"
        case .textCMD: return "text/cmd"
        case .textCSS: return "text/css"
        case .textCSV: return "text/csv"
        case .textHTML: return "text/html"
        case .textJavaScript: return "text/javascript"
        case .textPlain: return "text/plain"
        case .textPHP: return "text/php"
        case .textXML: return "text/xml"
        case .textMarkdown: return "text/markdown"
        case .textCacheManifest: return "text/cache-manifest"
        case let .custom(value): return value
        }
    }

    public var description: String { self.rawValue }
}
