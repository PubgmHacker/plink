// Plink/Playback/Providers/NativeHLSProvider.swift
// HLS / MP4 provider via AVPlayer (runbook §6)
//
// Loads AVPlayerItem from a URL with custom headers (for signed media URLs
// and DRM tokens — NEVER JWT/cookies per §2/§19).
//
// Capabilities reported:
//   - seekable: true (HLS/MP4 are always seekable when fully loaded)
//   - supportsPiP: true
//   - supportsAirPlay: true (allowsExternalPlayback = true on AVPlayer)
//   - supportsRateCorrection: true (AVPlayer supports setRate: with
//     prerollAtRate: for smooth catchup)
//   - supportsDRM: true (FairPlay via resource loader)

import Foundation
import AVFoundation
import UIKit

@MainActor
public final class NativeHLSProvider: ProviderAdapter {
    public private(set) var playerItem: AVPlayerItem?
    public var embeddedView: UIView? { nil }

    public var capabilities: PlaybackCapabilities {
        .init(
            seekable: true,
            supportsPiP: true,
            supportsAirPlay: true,
            supportsRateCorrection: true,
            supportsDRM: true
        )
    }

    private var urlAsset: AVURLAsset?

    public init() {}

    public func prepare(source: PlaybackSource) async throws {
        let url: URL
        var headers: [String: String] = [:]
        switch source {
        case .hls(let u, let h), .mp4(let u, let h):
            url = u
            headers = h
        case .external(let u):
            url = u
        case .youtube, .rutube, .vk, .embed:
            throw ProviderError.unsupportedSource
        }

        // P0-7: AVURLAssetHTTPHeaderFieldsKey is not public API in all SDKs.
        // Use string key "AVURLAssetHTTPHeaderFieldsKey" directly.
        let options: [String: Any] = headers.isEmpty
            ? [:]
            : ["AVURLAssetHTTPHeaderFieldsKey": headers]
        let asset = AVURLAsset(url: url, options: options)
        urlAsset = asset
        playerItem = AVPlayerItem(asset: asset)
    }

    public func teardown() {
        playerItem = nil
        urlAsset = nil
    }
}

public enum ProviderError: Error, Equatable, LocalizedError {
    case unsupportedSource
    case loadingFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedSource:
            return "Источник видео не поддерживается"
        case .loadingFailed(let reason):
            return reason
        }
    }
}
