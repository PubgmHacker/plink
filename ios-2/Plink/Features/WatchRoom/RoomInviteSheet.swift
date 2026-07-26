import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - Room Invite Sheet (M14)
// «Пригласить» одной кнопкой: QR-код + шер-линк + копирование кода.
// QR ведёт на https://plink.app/join/<roomId> (universal link из M12).

struct RoomInviteSheet: View {
    let model: WatchRoomModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var accent: Color { PlinkRoomAccent.current }

    var body: some View {
        VStack(spacing: 20) {
            Capsule().fill(.white.opacity(0.22)).frame(width: 36, height: 4).padding(.top, 10)

            Text("Пригласить в комнату")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Cinema2026.text)

            if let qr = Self.qrImage(for: model.roomFallbackURL.absoluteString) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("QR-код приглашения")
            }

            VStack(spacing: 4) {
                Text("КОД КОМНАТЫ")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(1.8)
                    .foregroundStyle(Cinema2026.secondary)
                Text(model.displayRoomCode)
                    .font(.system(size: 34, weight: .black, design: .monospaced))
                    .foregroundStyle(accent)
            }

            VStack(spacing: 10) {
                ShareLink(item: model.roomShareText) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Поделиться ссылкой")
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(accent, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }

                Button {
                    UIPasteboard.general.string = model.roomShareText
                    copied = true
                    HapticManager.impact(.light)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Скопировано" : "Скопировать приглашение")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Cinema2026.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Cinema2026.background.ignoresSafeArea())
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
    }

    static func qrImage(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
