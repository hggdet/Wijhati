import UIKit
import SceneKit
import MapLibre
import CoreLocation

/// A real 3D landmark model pinned to its true coordinates on the map
/// (proof of concept: Buckingham Palace, London — the Fenn-style demo).
///
/// MapLibre Native has no custom-layer 3D API like GL JS, so the model
/// lives in a transparent SceneKit view floating over the map. On every
/// camera change we re-derive everything from the map itself:
///   • position — the anchor coordinate projected to a screen point
///   • scale    — metres-per-point measured from two projected points
///   • heading  — the scene camera yaws with the map camera
///   • pitch    — the scene camera tilts with the map camera
/// so the model stays glued to the ground while the user pans, zooms,
/// rotates and tilts. The palace is built from primitives at real-world
/// scale (1 scene unit = 1 metre): the famous east front is ~108 m wide
/// and ~24 m tall and faces +X (east, toward the Mall).
final class LandmarkOverlay {
    /// Buckingham Palace, London.
    static let anchor = CLLocationCoordinate2D(latitude: 51.501364, longitude: -0.141889)
    /// The overlay only appears at street-level zoom.
    static let minZoom = 14.8
    /// Floating window size in points (the palace spans ~290 pt at z18).
    private static let window: CGFloat = 720

    let view: SCNView
    private let yawNode = SCNNode()
    private let pitchNode = SCNNode()
    private let cameraNode = SCNNode()
    private let camera = SCNCamera()

    init() {
        view = SCNView(frame: CGRect(x: 0, y: 0, width: Self.window, height: Self.window))
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true

        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        // Lights: soft ambient + one directional "sun".
        let ambient = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 620
        ambient.light = ambientLight
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        let sunLight = SCNLight()
        sunLight.type = .directional
        sunLight.intensity = 780
        sun.light = sunLight
        sun.eulerAngles = SCNVector3(-0.7, 0.4, -0.3)
        scene.rootNode.addChildNode(sun)

        scene.rootNode.addChildNode(Self.buildPalace())

        // Camera rig: yaw (map heading) → pitch (map tilt) → ortho camera.
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 400
        camera.zNear = 1
        camera.zFar = 5000
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 1200)
        pitchNode.addChildNode(cameraNode)
        yawNode.addChildNode(pitchNode)
        scene.rootNode.addChildNode(yawNode)

        view.scene = scene
        view.isHidden = true
    }

    func attach(to map: MLNMapView) {
        map.addSubview(view)
        sync(map: map)
    }

    func detach() {
        view.removeFromSuperview()
    }

    /// Recompute position, scale, heading and pitch from the map camera.
    func sync(map: MLNMapView) {
        guard map.zoomLevel >= Self.minZoom else { view.isHidden = true; return }
        let pt = map.convert(Self.anchor, toPointTo: map)
        let bounds = map.bounds.insetBy(dx: -60, dy: -60)
        guard bounds.contains(pt) else { view.isHidden = true; return }

        // Metres per point at the anchor, measured through the map's own
        // projection (100 m due north), so pitch foreshortening is included.
        var north = Self.anchor
        north.latitude += 100.0 / 111_320.0
        let ptN = map.convert(north, toPointTo: map)
        let dy = abs(ptN.y - pt.y)
        guard dy > 0.5 else { view.isHidden = true; return }
        camera.orthographicScale = Double(100.0 / dy) * Double(Self.window)

        let heading = map.camera.heading * Double.pi / 180.0
        let pitch = Double(map.camera.pitch) * Double.pi / 180.0
        yawNode.rotation = SCNVector4(0, 1, 0, Float(-heading))
        pitchNode.rotation = SCNVector4(1, 0, 0, Float(pitch - Double.pi / 2))

        view.center = pt
        view.isHidden = false
    }

    // MARK: - The palace, from primitives, in metres

    private static func material(_ hex: UInt32) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        m.lightingModel = .lambert
        return m
    }

    private static func box(_ w: Double, _ h: Double, _ l: Double,
                            _ x: Double, _ y: Double, _ z: Double,
                            _ hex: UInt32) -> SCNNode {
        let g = SCNBox(width: CGFloat(w), height: CGFloat(h), length: CGFloat(l), chamferRadius: 0)
        let mat = material(hex)
        g.materials = Array(repeating: mat, count: 6)
        let n = SCNNode(geometry: g)
        n.position = SCNVector3(Float(x), Float(y), Float(z))
        return n
    }

    private static func buildPalace() -> SCNNode {
        let root = SCNNode()
        let stone: UInt32 = 0xD9D2C2
        let stoneDark: UInt32 = 0xC9C0AA
        let trim: UInt32 = 0xF4EFE3
        let roof: UInt32 = 0x565B66

        // Ground plinth (the gravel forecourt edge).
        root.addChildNode(box(52, 0.6, 132, 2, 0.3, 0, 0xCFC8B4))
        // Main east-front block: 108 m long (N–S), 33 m deep, 24 m high.
        root.addChildNode(box(33, 24, 108, 0, 12, 0, stone))
        // Slightly darker service wings returning west at both ends.
        root.addChildNode(box(28, 17, 22, -26, 8.5, -43, stoneDark))
        root.addChildNode(box(28, 17, 22, -26, 8.5, 43, stoneDark))
        // Roof slab + parapet line.
        root.addChildNode(box(35, 1.8, 110, 0, 24.6, 0, roof))
        root.addChildNode(box(34, 1.2, 109, 0, 23.4, 0, trim))
        // Storey bands across the facade.
        root.addChildNode(box(0.5, 0.9, 108, 16.6, 8, 0, trim))
        root.addChildNode(box(0.5, 0.9, 108, 16.6, 16, 0, trim))
        // Central portico: podium, projecting block, columns, pediment.
        root.addChildNode(box(9, 2, 30, 19, 1, 0, stoneDark))
        root.addChildNode(box(5, 22, 26, 19, 13, 0, stone))
        for i in 0..<6 {
            let col = SCNCylinder(radius: 0.85, height: 14)
            col.firstMaterial = material(trim)
            let n = SCNNode(geometry: col)
            n.position = SCNVector3(22.2, 9, Float(-12.5 + Double(i) * 5))
            root.addChildNode(n)
        }
        let pediment = box(5.5, 4.5, 27, 19, 26.2, 0, trim)
        pediment.rotation = SCNVector4(0, 0, 1, Float(Double.pi / 4))
        pediment.scale = SCNVector3(1, 0.72, 1)
        root.addChildNode(pediment)
        root.addChildNode(box(6, 1.4, 28, 19, 24.4, 0, roof))
        // Queen Victoria Memorial, east of the palace on the roundabout.
        let memBase = SCNCylinder(radius: 4.2, height: 9)
        memBase.firstMaterial = material(trim)
        let memNode = SCNNode(geometry: memBase)
        memNode.position = SCNVector3(58, 4.5, 0)
        root.addChildNode(memNode)
        let gilded = SCNSphere(radius: 2.1)
        gilded.firstMaterial = material(0xE3B341)
        let gildNode = SCNNode(geometry: gilded)
        gildNode.position = SCNVector3(58, 11.5, 0)
        root.addChildNode(gildNode)
        return root
    }
}
