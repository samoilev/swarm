import MapKit
import SwiftUI

/// SwiftUI's `Map` says nothing when tiles never arrive — MapKit only reports load results
/// through `MKMapViewDelegate`. This is a throwaway `MKMapView` that rides alongside the real
/// map purely for those two callbacks, so the workspace can tell "still loading" from
/// "MapKit gave up".
///
/// It stays at the default world region rather than mirroring the visible one: a world view
/// needs a single tile, which is all it takes to learn whether tiles are reachable at all.
struct MapTileLoadProbe: NSViewRepresentable {
    /// `true` once tiles arrived, `false` when MapKit gave up on them. May fire more than once.
    let onResult: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }

    func makeNSView(context: Context) -> MKMapView {
        let view = MKMapView()
        view.delegate = context.coordinator
        view.isZoomEnabled = false
        view.isScrollEnabled = false
        view.isRotateEnabled = false
        view.isPitchEnabled = false
        view.showsCompass = false
        view.showsZoomControls = false
        return view
    }

    func updateNSView(_: MKMapView, context: Context) {
        context.coordinator.onResult = onResult
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onResult: (Bool) -> Void

        init(onResult: @escaping (Bool) -> Void) {
            self.onResult = onResult
        }

        func mapViewDidFinishLoadingMap(_: MKMapView) {
            onResult(true)
        }

        func mapViewDidFailLoadingMap(_: MKMapView, withError _: Error) {
            onResult(false)
        }
    }
}
