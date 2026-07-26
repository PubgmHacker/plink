import Foundation
import ReplayKit
import CoreVideo
import UIKit

// MARK: - Screen Capture Service
/// Захват экрана устройства через ReplayKit.
///
/// Два режима:
/// 1. **In-App capture** (RPScreenRecorder) — захват только внутри приложения,
///    без Broadcast Extension. Подходит для просмотра Кинопоиск/Иви в WebView.
/// 2. **System-wide capture** (Broadcast Extension) — захват всей системы,
///    требует отдельного extension target. Для стриминга любого контента.
///
/// Для Screen Share (основной режим) используем In-App capture — достаточно,
/// т.к. видео играет внутри нашего WebView.
@MainActor
final class ScreenCaptureService: NSObject, ObservableObject {

    @Published var isCapturing = false
    @Published var captureError: String?

    /// Текущий кадр (для Ambilight-сэмплера и WebRTC-кодирования).
    private(set) var currentSampleBuffer: CMSampleBuffer?

    private let recorder = RPScreenRecorder.shared()
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?

    // Колбэки
    var onFrame: ((CVPixelBuffer) -> Void)?
    var onError: ((String) -> Void)?

    // MARK: - Start / Stop

    func startCapture() async throws {
        guard !isCapturing else { return }

        // Проверяем доступность
        guard RPScreenRecorder.shared().isAvailable else {
            throw ScreenCaptureError.unavailable
        }

        recorder.isMicrophoneEnabled = false  // Звук через отдельный WebRTC audio track

        // RPSampleBufferType: .screen для видео
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recorder.startCapture(
                handler: { [weak self] sampleBuffer, sampleBufferType, error in
                    guard let self else { return }

                    if let error {
                        Task { @MainActor in
                            self.captureError = error.localizedDescription
                            self.onError?(error.localizedDescription)
                        }
                        return
                    }

                    if sampleBufferType == .video {
                        self.processVideoSampleBuffer(sampleBuffer)
                    }
                },
                completionHandler: { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }

        isCapturing = true
    }

    func stopCapture() async {
        guard isCapturing else { return }

        try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recorder.stopCapture { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        isCapturing = false
        currentSampleBuffer = nil
    }

    // MARK: - Frame Processing

    private func processVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        currentSampleBuffer = sampleBuffer

        // Извлекаем CVPixelBuffer для Ambilight и WebRTC
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Передаём кадр колбэкам
        onFrame?(pixelBuffer)
    }

    /// Запросить разрешение на захват экрана (показ системного диалога).
    func requestPermission() async -> Bool {
        // ReplayKit покажет системный диалог при startCapture
        return true
    }
}

// MARK: - Errors

enum ScreenCaptureError: LocalizedError {
    case unavailable
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Screen capture is not available on this device."
        case .permissionDenied:
            return "Screen capture permission was denied."
        }
    }
}

// MARK: - AVAssetWriterInputPixelBufferAdaptor stub
// (нужен для компиляции если захотим запись)
import AVFoundation
