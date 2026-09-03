//
//  AssistantOrbView.swift
//  Шейдерная сфера ИИ-ассистента (в стиле Siri / Салют / Алиса)
//
//  Использование (SwiftUI):
//
//      @State private var orbState: OrbState = .idle
//
//      var body: some View {
//          AssistantOrbView(state: orbState)
//              .frame(width: 280, height: 280)
//      }
//
//      // При смене состояния ассистента:
//      orbState = .listening   // сфера плавно перетечёт в новый цвет и ритм
//
//  Требования: iOS 15+, Metal (работает на устройствах и в симуляторе).
//
//  23.08.2026, Plink: перенесено из assistant-orb-ios как есть, с одной
//  адаптацией — прозрачный фон вместо зашитого тёмного. Сфера живёт на
//  онбординге вкладки ИИ поверх замыленной ленты, и непрозрачный MTKView
//  рисовал бы вокруг неё тёмный квадрат. Альфа = маска сферы + яркость
//  ореола, пайплайн — premultiplied blending.
//

import SwiftUI
import MetalKit

// MARK: - Состояния ассистента

public enum OrbState {
    case idle       // ожидание
    case listening  // слушает пользователя
    case thinking   // обрабатывает запрос
    case speaking   // отвечает
    case error      // ошибка / не расслышал

    var params: OrbParams {
        switch self {
        case .idle:
            return OrbParams(colA: rgb(0x2E4FD8), colB: rgb(0x7A5CF0), colC: rgb(0x35D0E8),
                             speed: 0.55, distort: 1.0, pulse: 0.30)
        case .listening:
            return OrbParams(colA: rgb(0x0FBF9F), colB: rgb(0x2FE38A), colC: rgb(0x6FE7FF),
                             speed: 0.75, distort: 1.6, pulse: 0.9)
        case .thinking:
            return OrbParams(colA: rgb(0xB65CF0), colB: rgb(0xF2A93B), colC: rgb(0xF26D8D),
                             speed: 0.5, distort: 2.4, pulse: 0.4)
        case .speaking:
            return OrbParams(colA: rgb(0xF04FA0), colB: rgb(0x4F6DF0), colC: rgb(0x8FE0FF),
                             speed: 1.0, distort: 1.4, pulse: 0.7)
        case .error:
            return OrbParams(colA: rgb(0xC4383F), colB: rgb(0xF2695C), colC: rgb(0xFFB38A),
                             speed: 0.45, distort: 1.1, pulse: 0.65, sway: 1)
        }
    }
}

public struct OrbParams {
    var colA: SIMD3<Float>
    var colB: SIMD3<Float>
    var colC: SIMD3<Float>
    var speed: Float
    var distort: Float
    var pulse: Float
    var sway: Float = 0   // покачивание «нет-нет» (для состояния ошибки)
}

private func rgb(_ hex: UInt32) -> SIMD3<Float> {
    SIMD3(Float((hex >> 16) & 0xFF) / 255,
          Float((hex >> 8) & 0xFF) / 255,
          Float(hex & 0xFF) / 255)
}

// MARK: - Uniforms (должны совпадать с MSL-структурой ниже)

private struct Uniforms {
    var resolution: SIMD2<Float> = .zero
    var time: Float = 0
    var speed: Float = 1
    var colA: SIMD3<Float> = .zero
    var distort: Float = 1
    var colB: SIMD3<Float> = .zero
    var pulse: Float = 0
    var colC: SIMD3<Float> = .zero
    var _pad: Float = 0
    var sway: Float = 0
    var flash: Float = 0
}

// MARK: - Metal-шейдер (тот же алгоритм, что в HTML-превью)

private let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 resolution;
    float  time;
    float  speed;
    float3 colA;
    float  distort;
    float3 colB;
    float  pulse;
    float3 colC;
    float  _pad;
    float  sway;
    float  flash;
};

vertex float4 orb_vertex(uint vid [[vertex_id]]) {
    // Полноэкранный треугольник
    float2 pos[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    return float4(pos[vid], 0, 1);
}

static float hash3(float3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

static float vnoise(float3 x) {
    float3 i = floor(x), f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(mix(hash3(i + float3(0,0,0)), hash3(i + float3(1,0,0)), f.x),
                   mix(hash3(i + float3(0,1,0)), hash3(i + float3(1,1,0)), f.x), f.y),
               mix(mix(hash3(i + float3(0,0,1)), hash3(i + float3(1,0,1)), f.x),
                   mix(hash3(i + float3(0,1,1)), hash3(i + float3(1,1,1)), f.x), f.y), f.z);
}

static float fbm(float3 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * vnoise(p); p = p * 2.02 + float3(13.7, 7.3, 3.1); a *= 0.5; }
    return v;
}

static float2x2 rot2(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, s), float2(-s, c));
}

fragment float4 orb_fragment(float4 pos [[position]],
                             constant Uniforms& u [[buffer(0)]]) {
    float2 frag = float2(pos.x, u.resolution.y - pos.y); // y вверх
    float2 uv = (frag * 2.0 - u.resolution) / min(u.resolution.x, u.resolution.y);
    // u.time — заранее накопленная фаза: смена скорости не даёт рывков
    float t = u.time;

    // органичное «дыхание» — всегда заметно, даже в покое
    float breathe = 0.5 * sin(t * 0.9) + 0.3 * sin(t * 1.7 + 1.3) + 0.2 * sin(t * 2.6 + 4.1);

    // лёгкое «парение» вверх-вниз, как в невесомости
    uv.y -= 0.012 * sin(t * 0.7);

    // покачивание «нет-нет» для состояния ошибки
    uv.x += 0.045 * u.sway * sin(t * 2.4);

    float R = 0.52 + (0.012 + 0.016 * u.pulse) * breathe + 0.005 * sin(t * 0.6) + 0.006 * u.flash;

    // апериодические импульсы энергии: раз в несколько секунд из случайной
    // точки вырывается вспышка и волной прокатывается по сфере
    float cyc = floor(t / 2.6);
    float ph  = fract(t / 2.6);
    float sd  = fract(sin(cyc * 12.9898) * 43758.5453);
    float sd2 = fract(sin(cyc * 78.233) * 24634.6345);
    float ip  = clamp((ph - sd * 0.35) / 0.7, 0.0, 1.0);
    float gate = step(0.0001, ph - sd * 0.35);
    float impulse = gate * exp(-3.2 * ip) * (0.55 + 0.45 * sd2) * (0.6 + 0.8 * u.pulse);
    float2 eo = float2(sd - 0.5, sd2 - 0.5) * R * 0.9;
    float er = length(uv - eo);
    float wfr = ip * R * 1.7;
    float wave = exp(-pow((er - wfr) * 14.0, 2.0)) * impulse;

    // импульс на мгновение раздувает сферу
    R += 0.010 * impulse * sin(min(ip * 6.2831, 3.14159));

    float r = length(uv);

    // Прозрачный фон: цвет копится с нуля, альфа считается в конце.
    float3 col = float3(0.0);
    float sphereA = 0.0;

    // мягкое двухслойное свечение
    if (r > R * 0.8) {
        float g  = exp(-(r - R) * 5.0);
        float g2 = exp(-(r - R) * 14.0);
        float ripple = 1.0 + 0.08 * u.pulse * sin(r * 14.0 - t * 1.8);
        col += mix(u.colA, u.colB, 0.5) * (g * 0.28 + g2 * 0.22) * ripple * (1.0 + 0.10 * breathe + 0.20 * u.flash);
        // волна импульса, выходящая за край, подсвечивает ореол
        col += mix(u.colC, float3(1.0), 0.4) * wave * 0.22;
    }

    // поверхность сферы
    if (r < R + 0.01) {
        float3 n = float3(uv, sqrt(max(0.0, R * R - r * r))) / R;

        // медленное вращение шумового поля
        float3 p = n;
        float2 xz = rot2(t * 0.12) * float2(p.x, p.z);
        p.x = xz.x; p.z = xz.y;

        // двойное доменное искажение — «жидкая» многослойная структура
        float2 q = float2(fbm(p * 2.0 + float3(0.0, 0.0, t * 0.28)),
                          fbm(p * 2.0 + float3(5.2, 1.3, t * 0.22)));
        float2 w = float2(fbm(p * 2.1 + 1.6 * u.distort * float3(q, q.x) + float3(1.7, 9.2, t * 0.18)),
                          fbm(p * 2.1 + 1.6 * u.distort * float3(q.y, q.x, q.x) + float3(8.3, 2.8, t * 0.20)));
        float f = fbm(p * 2.6 + 2.0 * u.distort * float3(w, w.x) + wave * 0.6);

        // богатое смешение цветов из слоёв искажения
        float3 base = mix(u.colA, u.colB, smoothstep(0.15, 0.85, f));
        base = mix(base, u.colC, smoothstep(0.4, 0.9, q.y) * 0.6);
        base += u.colB * w.x * w.x * 0.35;

        // дрейфующая «аврора»
        float band = smoothstep(0.25, 0.0, fabs(n.y - 0.35 * sin(t * 0.4) - 0.5 * (q.x - 0.5)));
        base = mix(base, mix(u.colC, float3(1.0), 0.25), band * 0.30);

        // тёмные прожилки для глубины
        float veins = smoothstep(0.45, 0.52, fabs(fract(f * 3.0 + w.y) - 0.5));
        base *= 0.82 + 0.18 * veins;

        // освещение: глубина + френелевский край
        float fres = pow(1.0 - n.z, 2.5);
        float3 surf = base * (0.40 + 0.72 * n.z) + u.colB * fres * 0.75;

        // внутреннее светящееся ядро
        float core = pow(max(0.0, 1.0 - r / (R * 0.75)), 2.0);
        surf += mix(u.colC, float3(1.0), 0.3) * core * (0.20 + 0.12 * breathe * (0.35 + 0.65 * u.pulse));

        // бегущая волна энергии + вспышка ядра в момент импульса
        surf += mix(u.colC, float3(1.0), 0.5) * wave * 0.55;
        surf += mix(u.colC, float3(1.0), 0.3) * core * impulse * 0.30;

        // яркий акцент-вспышка при смене состояния
        surf += mix(u.colC, float3(1.0), 0.5) * core * u.flash * 0.28;

        // два источника света
        float hl = pow(max(0.0, dot(n, normalize(float3(-0.45, 0.55, 0.72)))), 6.0);
        surf += float3(1.0) * hl * 0.20;
        float rim2 = pow(max(0.0, dot(n, normalize(float3(0.6, -0.35, 0.55)))), 8.0);
        surf += u.colC * rim2 * 0.15;

        float alpha = smoothstep(R + 0.006, R - 0.006, r);
        col = mix(col, surf, alpha);
        sphereA = alpha;
    }

    col *= 1.0 - 0.25 * smoothstep(0.6, 1.6, length(uv));
    // Premultiplied: ореол полупрозрачен по своей яркости, тело сферы —
    // по маске края.
    float lum = max(col.r, max(col.g, col.b));
    float outA = clamp(sphereA + lum * (1.0 - sphereA), 0.0, 1.0);
    return float4(col, outA);
}
"""

// MARK: - Рендерер

final class OrbRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    private var uniforms = Uniforms()
    private var current: OrbParams = OrbState.idle.params
    var target: OrbParams = OrbState.idle.params

    /// Опционально: уровень громкости микрофона/речи (0...1),
    /// чтобы сфера пульсировала в такт голосу.
    var audioLevel: Float = 0

    /// Вспышка-акцент при смене состояния (ставится обёрткой, затухает сама)
    var flash: Float = 0

    private var lastTime = CACurrentMediaTime()
    private var phase: Float = 12.0 // накопленная фаза анимации

    init?(view: MTKView) {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue

        do {
            let lib = try device.makeLibrary(source: shaderSource, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = lib.makeFunction(name: "orb_vertex")
            desc.fragmentFunction = lib.makeFunction(name: "orb_fragment")
            desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
            // Premultiplied-alpha blending — под прозрачный фон вью.
            desc.colorAttachments[0].isBlendingEnabled = true
            desc.colorAttachments[0].rgbBlendOperation = .add
            desc.colorAttachments[0].alphaBlendOperation = .add
            desc.colorAttachments[0].sourceRGBBlendFactor = .one
            desc.colorAttachments[0].sourceAlphaBlendFactor = .one
            desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("Orb shader error: \\(error)")
            return nil
        }

        view.device = device
        view.preferredFramesPerSecond = 60
        super.init()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = Float(min(now - lastTime, 0.05))
        lastTime = now

        // Плавный переход между состояниями (мягче, чем в v1)
        let k = 1 - exp(-dt * 3.0)
        current.colA = mix(current.colA, target.colA, k)
        current.colB = mix(current.colB, target.colB, k)
        current.colC = mix(current.colC, target.colC, k)
        current.speed += (target.speed - current.speed) * k
        current.distort += (target.distort - current.distort) * k
        let pulseTarget = min(1.0, target.pulse + audioLevel * 0.6)
        current.pulse += (pulseTarget - current.pulse) * k
        current.sway += (target.sway - current.sway) * k
        flash *= exp(-dt * 2.6) // затухание вспышки
        phase += dt * current.speed // фаза идёт вперёд без скачков

        uniforms.resolution = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        uniforms.time = phase
        uniforms.speed = current.speed
        uniforms.distort = current.distort
        uniforms.pulse = current.pulse
        uniforms.colA = current.colA
        uniforms.colB = current.colB
        uniforms.colC = current.colC
        uniforms.sway = current.sway
        uniforms.flash = flash

        guard let drawable = view.currentDrawable,
              let rpd = view.currentRenderPassDescriptor,
              let cmd = queue.makeCommandBuffer(),
              let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) else { return }

        enc.setRenderPipelineState(pipeline)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()
        cmd.present(drawable)
        cmd.commit()
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ k: Float) -> SIMD3<Float> {
        a + (b - a) * k
    }
}

// MARK: - SwiftUI-обёртка

public struct AssistantOrbView: UIViewRepresentable {
    public var state: OrbState
    public var audioLevel: Float

    public init(state: OrbState, audioLevel: Float = 0) {
        self.state = state
        self.audioLevel = audioLevel
    }

    public func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.framebufferOnly = true
        view.isOpaque = false
        view.backgroundColor = .clear
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        (view.layer as? CAMetalLayer)?.isOpaque = false
        if let renderer = OrbRenderer(view: view) {
            context.coordinator.renderer = renderer
            view.delegate = renderer
        }
        return view
    }

    public func updateUIView(_ uiView: MTKView, context: Context) {
        if context.coordinator.lastState != state {
            context.coordinator.lastState = state
            context.coordinator.renderer?.flash = 0.8 // мягкая вспышка при переходе
        }
        context.coordinator.renderer?.target = state.params
        context.coordinator.renderer?.audioLevel = audioLevel
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        var renderer: OrbRenderer?
        var lastState: OrbState = .idle
    }
}

// MARK: - Превью

#if DEBUG
#endif
